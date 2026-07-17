import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../state/providers.dart';
import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';
import 'servarr_options_dialog.dart';

/// Release picker (movies only — the Sonarr/series picker is out of scope, so
/// series use the season chooser). Mirrors `FindDownload.tsx`'s `ReleasePicker`,
/// including the `createdByPicker` cleanup lifecycle that keeps the Radarr DB
/// clean:
///   open  → POST /radarr/releases (adds the title monitored+no-search if it
///           isn't in Radarr yet, then runs the live interactive search)
///   grab  → POST /radarr/grab     (hand the release to the client, KEEP entry)
///   close → POST /radarr/releases/cancel (remove ONLY an entry this picker
///           created — fires on every close/unmount path exactly once, and
///           never after a successful grab).
Future<void> showServarrReleasePicker(
  BuildContext context, {
  required ServarrTitle item,
  required VoidCallback onGrabbed,
  required VoidCallback onManual,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.66),
    builder: (_) =>
        _ReleasePicker(item: item, onGrabbed: onGrabbed, onManual: onManual),
  );
}

class _Release {
  _Release(this.raw);
  final Map<String, dynamic> raw;
  String get guid => (raw['guid'] ?? '').toString();
  String get title => (raw['title'] ?? '').toString();
  String? get indexer => raw['indexer'] as String?;
  int? get indexerId => raw['indexerId'] as int?;
  int? get size => (raw['size'] as num?)?.toInt();
  int? get seeders => (raw['seeders'] as num?)?.toInt();
  int? get leechers => (raw['leechers'] as num?)?.toInt();
  String? get quality => raw['quality'] as String?;
  bool get rejected => raw['rejected'] == true;
  List<String> get rejections =>
      ((raw['rejections'] as List?) ?? const []).map((e) => e.toString()).toList();
}

class _ReleaseData {
  _ReleaseData({
    required this.movieId,
    this.createdByPicker,
    this.searchFailed,
    this.releases = const [],
  });
  final int? movieId;
  final bool? createdByPicker;
  final bool? searchFailed;
  final List<_Release> releases;

  static _ReleaseData parse(dynamic value) {
    if (value is! Map || value['movieId'] is! int) {
      return _ReleaseData(movieId: null);
    }
    return _ReleaseData(
      movieId: value['movieId'] as int?,
      createdByPicker: value['createdByPicker'] as bool?,
      searchFailed: value['searchFailed'] as bool?,
      releases: ((value['releases'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => _Release(e.cast<String, dynamic>()))
          .where((r) => r.guid.isNotEmpty)
          .toList(),
    );
  }
}

class _ReleasePicker extends ConsumerStatefulWidget {
  const _ReleasePicker({
    required this.item,
    required this.onGrabbed,
    required this.onManual,
  });
  final ServarrTitle item;
  final VoidCallback onGrabbed;
  final VoidCallback onManual;

  @override
  ConsumerState<_ReleasePicker> createState() => _ReleasePickerState();
}

class _ReleasePickerState extends ConsumerState<_ReleasePicker> {
  bool _loading = true;
  String? _error;
  _ReleaseData? _data;
  String? _grabbing;
  String? _grabError;

  // Cleanup lifecycle — a single settled guard shared between dispose (any
  // close path) and the post-dispose async resolve, so a fileless entry the
  // picker created is cancelled at most once and never after a grab.
  bool _settled = false;
  bool _disposed = false;
  int? _movieId;
  bool _createdByPicker = false;

  // Cached so the cleanup path can cancel without touching `ref` during dispose.
  late final ApiClient _api = ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    if (_settled) return;
    _settled = true;
    if (_createdByPicker && _movieId != null) {
      _cancel(_movieId!);
    }
  }

  void _cancel(int movieId) {
    // Fire-and-forget; the server re-checks the entry is fileless + unqueued.
    _api
        .servarrPost('radarr/releases/cancel',
            body: {'movieId': movieId, 'createdByPicker': true})
        .catchError((_) => null);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _grabError = null;
    });
    try {
      final api = _api;
      final existing = _movieId;
      var createdByPicker = _createdByPicker;
      Object body;
      if (existing != null) {
        body = {'movieId': existing};
      } else if (widget.item.isAdded) {
        body = {'movieId': widget.item.id};
        createdByPicker = false;
      } else {
        final meta = await ref.read(servarrMetaProvider(ServarrKind.movie).future);
        if (meta == null) throw Exception('meta');
        body = {
          'movie': widget.item.raw,
          'qualityProfileId': meta.qualityProfileId,
          'rootFolderPath': meta.rootFolderPath,
        };
      }
      final res = await api.servarrPost('radarr/releases', body: body);
      final data = _ReleaseData.parse(res);
      // A passed movieId reports createdByPicker:false, but we keep our own flag
      // so a retried browse still cleans up on close.
      final resolvedCreated =
          existing != null ? createdByPicker : (data.createdByPicker ?? false);
      if (_disposed) {
        // Unmounted mid-search — still remove an entry we just created.
        if (resolvedCreated && data.movieId != null) _cancel(data.movieId!);
        return;
      }
      setState(() {
        _movieId = data.movieId;
        _createdByPicker = resolvedCreated;
        _settled = false;
        _data = data;
        _loading = false;
      });
    } catch (_) {
      if (_disposed) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t load sources right now. Please try again.';
      });
    }
  }

  Future<void> _grab(_Release rel) async {
    if (_grabbing != null) return;
    setState(() {
      _grabbing = rel.guid;
      _grabError = null;
    });
    try {
      await _api.servarrPost('radarr/grab', body: {
        'movieId': _movieId,
        'guid': rel.guid,
        'indexerId': rel.indexerId,
      });
      _settled = true; // keep the entry; parent flips the card to downloading
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onGrabbed();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _grabbing = null;
        _grabError = 'Couldn\'t start that download. Try another source.';
      });
    }
  }

  void _openManual() {
    Navigator.of(context).pop();
    widget.onManual();
  }

  @override
  Widget build(BuildContext context) {
    final releases = _data?.releases ?? const <_Release>[];
    return ServarrDialogShell(
      maxWidth: 640,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServarrDialogHeader(
            eyebrow: 'CHOOSE A RELEASE',
            title: widget.item.title,
            onClose: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 34),
              child: Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(height: AppSpacing.md),
                  Text(
                    'Searching every source for the healthiest release. '
                    'This can take up to a minute.',
                    textAlign: TextAlign.center,
                    style: AppTheme.dim,
                  ),
                ],
              ),
            )
          else if (_error != null)
            _ErrorActions(
              text: _error!,
              onRetry: _load,
              onManual: _openManual,
            )
          else if (_data?.searchFailed == true)
            _ErrorActions(
              text: 'Couldn\'t reach the sources just now. Please try again.',
              onRetry: _load,
              onManual: _openManual,
            )
          else if (releases.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ServarrNotice(
                  icon: Icons.search_off,
                  text: 'No sources found for this title right now.',
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton(
                  label: 'Add source',
                  icon: Icons.add,
                  variant: AppButtonVariant.secondary,
                  onPressed: _openManual,
                ),
              ],
            )
          else ...[
            if (_grabError != null) ...[
              ServarrNotice(icon: Icons.error_outline, text: _grabError!),
              const SizedBox(height: AppSpacing.md),
            ],
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: releases.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _ReleaseRow(
                  release: releases[i],
                  grabbing: _grabbing,
                  onGrab: () => _grab(releases[i]),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(Icons.error_outline, size: 13, color: context.wp.faint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Greyed rows were skipped by the auto-picker for the reason shown.',
                    style: TextStyle(fontSize: 12, color: context.wp.faint),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorActions extends StatelessWidget {
  const _ErrorActions({
    required this.text,
    required this.onRetry,
    required this.onManual,
  });
  final String text;
  final VoidCallback onRetry;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ServarrNotice(icon: Icons.error_outline, text: text),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            AppButton(
              label: 'Try again',
              icon: Icons.search,
              variant: AppButtonVariant.primary,
              onPressed: onRetry,
            ),
            AppButton(
              label: 'Add source',
              icon: Icons.add,
              variant: AppButtonVariant.secondary,
              onPressed: onManual,
            ),
          ],
        ),
      ],
    );
  }
}

class _ReleaseRow extends StatelessWidget {
  const _ReleaseRow({
    required this.release,
    required this.grabbing,
    required this.onGrab,
  });
  final _Release release;
  final String? grabbing;
  final VoidCallback onGrab;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final rejected = release.rejected;
    final busy = grabbing == release.guid;
    final anyBusy = grabbing != null;
    final seeds = release.seeders;
    final seedColor = seeds == null
        ? wp.faint
        : seeds > 0
            ? wp.text
            : AppColors.red;
    final reason = rejected
        ? (release.rejections.isNotEmpty
            ? release.rejections.first
            : 'Skipped by the quality profile')
        : null;

    return Opacity(
      opacity: rejected ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: wp.surface2.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: wp.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    release.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono.copyWith(fontSize: 12.5, color: wp.text),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (release.quality != null && release.quality!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: wp.text.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text(
                            release.quality!,
                            style: AppTheme.mono.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: wp.dim,
                            ),
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: seedColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${seeds ?? '—'} seed${seeds == 1 ? '' : 's'}',
                            style: AppTheme.mono.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: seedColor,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${release.leechers ?? '—'} peers',
                        style: AppTheme.mono.copyWith(fontSize: 12, color: wp.faint),
                      ),
                      Text(
                        fmtSize(release.size),
                        style: AppTheme.mono.copyWith(fontSize: 12, color: wp.dim),
                      ),
                      if (release.indexer != null && release.indexer!.isNotEmpty)
                        Text(
                          release.indexer!,
                          style: AppTheme.mono.copyWith(fontSize: 12, color: wp.faint),
                        ),
                    ],
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(Icons.error_outline, size: 13, color: wp.dim),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: wp.dim),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!rejected) ...[
              const SizedBox(width: AppSpacing.md),
              AppButton(
                label: busy ? 'Starting…' : 'Download',
                icon: busy ? null : Icons.download,
                busy: busy,
                variant: AppButtonVariant.primary,
                onPressed: anyBusy ? null : onGrab,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
