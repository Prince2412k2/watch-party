import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../state/providers.dart';
import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';
import 'servarr_options_dialog.dart';

/// Submit a magnet link or a `.torrent` file for a Discover title (mirrors
/// `FindDownload.tsx`'s `ManualSourceDialog`). Adds the title to Radarr/Sonarr
/// first if needed (resolveTargetId), then POSTs `/manual/magnet` (JSON) or
/// uploads the raw `.torrent` body via `ApiClient.manualTorrentUpload`
/// (`application/x-bittorrent`, ≤2 MiB). This is the Discover detail screen's
/// "Add source" entry — kept as-is when it was extracted out of
/// `servarr_detail_screen.dart` so movie behaviour didn't change at all.
Future<void> showServarrManualSourceDialog(
  BuildContext context, {
  required ServarrTitle item,
  required ServarrKind kind,
  required VoidCallback onSubmitted,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (_) =>
        _ManualSourceDialog(item: item, kind: kind, onSubmitted: onSubmitted),
  );
}

class _ManualSourceDialog extends ConsumerStatefulWidget {
  const _ManualSourceDialog({
    required this.item,
    required this.kind,
    required this.onSubmitted,
  });
  final ServarrTitle item;
  final ServarrKind kind;
  final VoidCallback onSubmitted;

  @override
  ConsumerState<_ManualSourceDialog> createState() =>
      _ManualSourceDialogState();
}

class _ManualSourceDialogState extends ConsumerState<_ManualSourceDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.kind == ServarrKind.movie
        ? [widget.item.title, widget.item.year]
            .where((e) => e != null && e.toString().isNotEmpty)
            .join('.')
        : widget.item.title,
  );
  final _magnet = TextEditingController();
  final _season = TextEditingController();
  final _episode = TextEditingController();

  late bool _magnetMode = widget.magnetFirst;
  PlatformFile? _torrent;
  bool _submitting = false;
  String? _error;
  bool _ok = false;

  bool get _isSeries => widget.kind == ServarrKind.series;
  String get _service => widget.kind.service;

  @override
  void dispose() {
    _title.dispose();
    _magnet.dispose();
    _season.dispose();
    _episode.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _title.text.trim().isNotEmpty &&
      (_magnetMode ? _magnet.text.trim().isNotEmpty : _torrent != null) &&
      !_submitting &&
      !_ok;

  Future<void> _pickTorrent() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['torrent'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    if (file.size > maxTorrentBytes) {
      setState(() {
        _torrent = null;
        _error = 'Torrent files must be 2 MiB or smaller.';
      });
      return;
    }
    setState(() {
      _torrent = file;
      _error = null;
    });
  }

  /// Resolve the Radarr/Sonarr id to attach the source to, adding the title
  /// (monitor, no search) if it isn't in the library yet.
  Future<int> _resolveTargetId() async {
    final api = ref.read(apiClientProvider);
    if (widget.item.id != null && widget.item.id! > 0) return widget.item.id!;
    final meta = await ref.read(servarrMetaProvider(widget.kind).future);
    if (meta == null) throw Exception('Download options are unavailable.');
    final body = widget.kind == ServarrKind.movie
        ? {
            'movie': widget.item.raw,
            'qualityProfileId': meta.qualityProfileId,
            'rootFolderPath': meta.rootFolderPath,
            'monitor': true,
            'searchNow': false,
          }
        : {
            'series': widget.item.raw,
            'qualityProfileId': meta.qualityProfileId,
            'rootFolderPath': meta.rootFolderPath,
            'languageProfileId': meta.languageProfileId,
            'monitor': true,
            'searchNow': false,
          };
    final added = await api.servarrPost('$_service/add', body: body);
    if (added is Map && added['id'] is int) return added['id'] as int;

    final library = await api.servarrGet(
      '$_service/${widget.kind == ServarrKind.movie ? 'movies' : 'series'}',
    );
    final existing = (library as List).cast<Map<String, dynamic>>().firstWhere(
      (c) => widget.kind == ServarrKind.movie
          ? c['tmdbId'] == widget.item.tmdbId
          : c['tvdbId'] == widget.item.tvdbId,
      orElse: () => const {},
    );
    final id = existing['id'];
    if (id is int) return id;
    throw Exception('Could not prepare this title in the library.');
  }

  /// Shell the series into Sonarr just enough to own the manual download. The
  /// server route is the same resolver the release picker uses, so a series that
  /// is already there is found rather than duplicated.
  Future<int> _resolveSeriesId(ApiClient api) async {
    final meta = await ref.read(servarrMetaProvider(ServarrKind.series).future);
    if (meta == null) {
      throw ApiException('sonarr/resolve', 503, 'Sonarr is not configured.');
    }
    final res = await api.servarrPost('sonarr/resolve', body: {
      'series': widget.seriesRaw,
      'qualityProfileId': meta.qualityProfileId,
      'languageProfileId': meta.languageProfileId,
      'rootFolderPath': meta.rootFolderPath,
    });
    final id = (res is Map ? res['seriesId'] : null) as int?;
    if (id == null) {
      throw ApiException('sonarr/resolve', 502, 'Sonarr did not return a series.');
    }
    return id;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final targetId = await _resolveTargetId();
      final seasonNumber =
          _isSeries && _season.text.isNotEmpty ? int.tryParse(_season.text) : null;
      final episodeNumber = _isSeries &&
              _season.text.isNotEmpty &&
              _episode.text.isNotEmpty
          ? int.tryParse(_episode.text)
          : null;

      if (_magnetMode) {
        await api.servarrPost('manual/magnet', body: {
          'service': _service,
          'targetId': targetId,
          'title': _title.text.trim(),
          'magnet': _magnet.text.trim(),
          if (seasonNumber != null) 'seasonNumber': seasonNumber,
          if (episodeNumber != null) 'episodeNumber': episodeNumber,
        });
      } else {
        final file = _torrent!;
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        await api.manualTorrentUpload(
          bytes,
          service: _service,
          targetId: '$targetId',
          title: _title.text.trim(),
          seasonNumber: seasonNumber,
          episodeNumber: episodeNumber,
        );
      }
      if (!mounted) return;
      setState(() {
        _ok = true;
        _submitting = false;
      });
      widget.onSubmitted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not submit this source.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return ServarrDialogShell(
      maxWidth: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServarrDialogHeader(
            eyebrow: 'MANUAL SOURCE',
            title: 'Add a source for ${widget.item.title}',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Mode toggle.
          Row(
            children: [
              _ModeTab(
                label: 'Magnet link',
                selected: _magnetMode,
                onTap: () => setState(() {
                  _magnetMode = true;
                  _error = null;
                }),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ModeTab(
                label: '.torrent file',
                selected: !_magnetMode,
                onTap: () => setState(() {
                  _magnetMode = false;
                  _error = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _label('Release title'),
          _ManualSourceTextField(
            controller: _title,
            hint: _isSeries
                ? 'Series.Title.S01E01.1080p.WEB-DL'
                : 'Movie.Title.2026.1080p.WEB-DL',
            mono: true,
            onChanged: (_) => setState(() {}),
          ),
          if (_isSeries) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Season (optional)'),
                      _ManualSourceTextField(
                        controller: _season,
                        hint: '',
                        mono: true,
                        number: true,
                        onChanged: (v) => setState(() {
                          if (v.isEmpty) _episode.clear();
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Episode (optional)'),
                      _ManualSourceTextField(
                        controller: _episode,
                        hint: '',
                        mono: true,
                        number: true,
                        enabled: _season.text.isNotEmpty,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_magnetMode) ...[
            _label('Magnet URI'),
            _ManualSourceTextField(
              controller: _magnet,
              hint: 'magnet:?xt=urn:btih:…',
              mono: true,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
          ] else ...[
            _label('Torrent file (maximum 2 MiB)'),
            Row(
              children: [
                AppButton(
                  label: _torrent == null ? 'Choose file' : 'Change file',
                  icon: Icons.attach_file,
                  variant: AppButtonVariant.secondary,
                  onPressed: _pickTorrent,
                ),
                const SizedBox(width: AppSpacing.md),
                if (_torrent != null)
                  Expanded(
                    child: Text(
                      _torrent!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono.copyWith(fontSize: 12.5, color: wp.dim),
                    ),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ServarrNotice(icon: Icons.error_outline, text: _error!),
          ],
          if (_ok) ...[
            const SizedBox(height: AppSpacing.md),
            const ServarrNotice(
              icon: Icons.check,
              text: 'Source submitted to Radarr/Sonarr for validation.',
              error: false,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: _submitting
                ? 'Submitting…'
                : _ok
                    ? 'Submitted'
                    : 'Submit source',
            icon: _ok ? Icons.check : Icons.add,
            busy: _submitting,
            expand: true,
            variant: _ok ? AppButtonVariant.secondary : AppButtonVariant.primary,
            onPressed: _canSubmit ? _submit : null,
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.wp.dim,
          ),
        ),
      );
}

/// Submit a magnet link or a `.torrent` file scoped to a series, season, or
/// episode (US-4/FR-010) — the show stage's right-click "Add source" entry.
/// Unlike [showServarrManualSourceDialog], the scope (which Sonarr series, and
/// optionally which season/episode) is already known from where the user
/// right-clicked, so there's no season/episode entry — just the release and
/// the magnet/torrent itself. [sonarrSeriesId] is the target the server's
/// `manual/magnet` / `manual/torrent` routes grab against; when it's null (a
/// Discover series not yet added to Sonarr) submission is blocked rather than
/// guessed at, since there is no id to attribute the download to.
Future<void> showManualSourceDialog(
  BuildContext context, {
  required String title,
  int? sonarrSeriesId,
  Map<String, dynamic>? seriesRaw,
  int? seasonNumber,
  int? episodeNumber,
  bool magnetFirst = true,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (_) => _ScopedManualSourceDialog(
      scopeTitle: title,
      sonarrSeriesId: sonarrSeriesId,
      seriesRaw: seriesRaw,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      magnetFirst: magnetFirst,
    ),
  );
}

class _ScopedManualSourceDialog extends ConsumerStatefulWidget {
  const _ScopedManualSourceDialog({
    required this.scopeTitle,
    required this.sonarrSeriesId,
    required this.seriesRaw,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.magnetFirst,
  });
  final String scopeTitle;
  final int? sonarrSeriesId;

  /// Sonarr lookup payload for a series that is not in the library yet — the
  /// submit path shells it in to get a targetId, so the manual route stays open
  /// for a Discover series (FR-019).
  final Map<String, dynamic>? seriesRaw;
  final int? seasonNumber;
  final int? episodeNumber;
  final bool magnetFirst;

  @override
  ConsumerState<_ScopedManualSourceDialog> createState() =>
      _ScopedManualSourceDialogState();
}

class _ScopedManualSourceDialogState
    extends ConsumerState<_ScopedManualSourceDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.scopeTitle);
  final _magnet = TextEditingController();

  bool _magnetMode = true;
  PlatformFile? _torrent;
  bool _submitting = false;
  String? _error;
  bool _ok = false;

  @override
  void dispose() {
    _title.dispose();
    _magnet.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      (widget.sonarrSeriesId != null || widget.seriesRaw != null) &&
      _title.text.trim().isNotEmpty &&
      (_magnetMode ? _magnet.text.trim().isNotEmpty : _torrent != null) &&
      !_submitting &&
      !_ok;

  Future<void> _pickTorrent() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['torrent'],
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    if (file.size > maxTorrentBytes) {
      setState(() {
        _torrent = null;
        _error = 'Torrent files must be 2 MiB or smaller.';
      });
      return;
    }
    setState(() {
      _torrent = file;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final targetId = widget.sonarrSeriesId ?? await _resolveSeriesId(api);
      if (_magnetMode) {
        await api.servarrPost('manual/magnet', body: {
          'service': 'sonarr',
          'targetId': targetId,
          'title': _title.text.trim(),
          'magnet': _magnet.text.trim(),
          if (widget.seasonNumber != null) 'seasonNumber': widget.seasonNumber,
          if (widget.episodeNumber != null)
            'episodeNumber': widget.episodeNumber,
        });
      } else {
        final file = _torrent!;
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        await api.manualTorrentUpload(
          bytes,
          service: 'sonarr',
          targetId: '$targetId',
          title: _title.text.trim(),
          seasonNumber: widget.seasonNumber,
          episodeNumber: widget.episodeNumber,
        );
      }
      if (!mounted) return;
      setState(() {
        _ok = true;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not submit this source.';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return ServarrDialogShell(
      maxWidth: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServarrDialogHeader(
            eyebrow: 'MANUAL SOURCE',
            title: 'Add a source for ${widget.scopeTitle}',
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (widget.sonarrSeriesId == null && widget.seriesRaw == null) ...[
            const ServarrNotice(
              icon: Icons.error_outline,
              text: 'This series isn\'t matched in Sonarr, so a manual source '
                  "can't be attributed to it.",
            ),
            const SizedBox(height: AppSpacing.lg),
          ] else if (widget.sonarrSeriesId == null) ...[
            const ServarrNotice(
              icon: Icons.info_outline,
              text: 'This series will be added to the library so the download '
                  'can be attributed to it.',
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          // Mode toggle.
          Row(
            children: [
              _ModeTab(
                label: 'Magnet link',
                selected: _magnetMode,
                onTap: () => setState(() {
                  _magnetMode = true;
                  _error = null;
                }),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ModeTab(
                label: '.torrent file',
                selected: !_magnetMode,
                onTap: () => setState(() {
                  _magnetMode = false;
                  _error = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _label('Release title'),
          _ManualSourceTextField(
            controller: _title,
            hint: 'Series.Title.S01E01.1080p.WEB-DL',
            mono: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_magnetMode) ...[
            _label('Magnet URI'),
            _ManualSourceTextField(
              controller: _magnet,
              hint: 'magnet:?xt=urn:btih:…',
              mono: true,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
            ),
          ] else ...[
            _label('Torrent file (maximum 2 MiB)'),
            Row(
              children: [
                AppButton(
                  label: _torrent == null ? 'Choose file' : 'Change file',
                  icon: Icons.attach_file,
                  variant: AppButtonVariant.secondary,
                  onPressed: _pickTorrent,
                ),
                const SizedBox(width: AppSpacing.md),
                if (_torrent != null)
                  Expanded(
                    child: Text(
                      _torrent!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono.copyWith(fontSize: 12.5, color: wp.dim),
                    ),
                  ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ServarrNotice(icon: Icons.error_outline, text: _error!),
          ],
          if (_ok) ...[
            const SizedBox(height: AppSpacing.md),
            const ServarrNotice(
              icon: Icons.check,
              text: 'Source submitted to Sonarr for validation.',
              error: false,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: _submitting
                ? 'Submitting…'
                : _ok
                    ? 'Submitted'
                    : 'Submit source',
            icon: _ok ? Icons.check : Icons.add,
            busy: _submitting,
            expand: true,
            variant: _ok ? AppButtonVariant.secondary : AppButtonVariant.primary,
            onPressed: _canSubmit ? _submit : null,
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.wp.dim,
          ),
        ),
      );
}

// ── Shared bits (mode tab, text field) ──────────────────────────────────────

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? wp.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          border: Border.all(color: selected ? Colors.transparent : wp.line2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: selected ? wp.onAccent : wp.dim,
          ),
        ),
      ),
    );
  }
}

class _ManualSourceTextField extends StatelessWidget {
  const _ManualSourceTextField({
    required this.controller,
    required this.hint,
    this.mono = false,
    this.number = false,
    this.maxLines = 1,
    this.enabled = true,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final bool mono;
  final bool number;
  final int maxLines;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: number ? TextInputType.number : null,
      onChanged: onChanged,
      style: (mono ? AppTheme.mono : AppTheme.label).copyWith(
        color: wp.text,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: wp.faint, fontSize: 13),
        filled: true,
        fillColor: wp.surface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: wp.line2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: wp.text.withValues(alpha: 0.4)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide: BorderSide(color: wp.line),
        ),
      ),
    );
  }
}
