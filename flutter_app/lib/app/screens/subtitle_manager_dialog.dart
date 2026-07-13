import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// "Audio and subtitles" — mirrors the web detail page's `DetailTrackMenu`:
/// lists the tracks Jellyfin reports for [itemId] via `playbackInfo`, and lets
/// the user upload a new external subtitle file or delete one they added.
/// Track *selection* for playback itself is handled in-player (the existing
/// audio/subtitle menus in `player_chrome.dart`) — this dialog only manages
/// what subtitle tracks exist, since that's the piece the web client has and
/// Flutter didn't.
Future<void> showSubtitleManagerDialog(BuildContext context, String itemId) {
  return sc.showDialog<void>(
    context: context,
    builder: (_) => _SubtitleManagerDialog(itemId: itemId),
  );
}

class _SubtitleManagerDialog extends ConsumerStatefulWidget {
  const _SubtitleManagerDialog({required this.itemId});
  final String itemId;

  @override
  ConsumerState<_SubtitleManagerDialog> createState() =>
      _SubtitleManagerDialogState();
}

class _SubtitleManagerDialogState
    extends ConsumerState<_SubtitleManagerDialog> {
  PlaybackInfo? _info;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await ref
          .read(apiClientProvider)
          .playbackInfo(widget.itemId);
      if (mounted) setState(() => _info = info);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa', 'sub'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file?.bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .uploadSubtitle(widget.itemId, file!.bytes!, file.name);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PlaybackTrack track) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .deleteSubtitle(widget.itemId, track.index);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(PlaybackTrack t, String fallback) {
    final base = t.displayTitle ?? t.title ?? t.language ?? fallback;
    return [
      base,
      if (t.isDefault) 'Default',
      if (t.isForced) 'Forced',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return AppDialog(
      title: 'Audio and subtitles',
      body: _error != null
          ? 'Failed to load tracks: $_error'
          : info == null
          ? 'Loading tracks…'
          : null,
      child: info == null
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info.audioStreams.isNotEmpty) ...[
                  const SectionHeader(title: 'Audio'),
                  for (final t in info.audioStreams)
                    _TrackRow(label: _label(t, 'Audio ${t.index}')),
                  const SizedBox(height: AppSpacing.md),
                ],
                const SectionHeader(title: 'Subtitles'),
                if (info.subtitleStreams.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(
                      'No subtitle tracks.',
                      style: TextStyle(color: AppColors.dim),
                    ),
                  ),
                for (final t in info.subtitleStreams)
                  _TrackRow(
                    label: _label(t, 'Subtitle ${t.index}'),
                    onDelete: t.isExternal && !_busy ? () => _delete(t) : null,
                  ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Upload subtitle',
                  icon: Icons.upload_file,
                  variant: AppButtonVariant.secondary,
                  onPressed: _busy ? null : _upload,
                ),
              ],
            ),
      actions: [
        AppButton(
          label: 'Close',
          variant: AppButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// A track row, built on shadcn/plain widgets — `ListTile` needs a `Material`
/// ancestor, which `sc.AlertDialog` doesn't provide.
class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.label, this.onDelete});
  final String label;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: AppColors.text)),
          ),
          if (onDelete != null)
            sc.IconButton.ghost(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
