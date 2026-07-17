import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../state/providers.dart';
import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/download_poster.dart';
import 'servarr_options_dialog.dart';
import 'servarr_release_picker.dart';
import 'servarr_season_chooser.dart';

/// Full-page Discover title detail (mirrors `FindDownload.tsx`'s `DetailView`):
/// a blurred backdrop hero with a theme wash, the 2:3 poster, MOVIE/SERIES
/// eyebrow, large title, rating + genres, mono info line, the acquire action(s),
/// and the overview. Movies get one-tap Download + Options + Release picker +
/// Add source + Remove; series get the season chooser. Rendered in-page by
/// [ServarrScreen] (the bottom nav + profile stay visible), so [onBack] just
/// clears the selection.
class ServarrDetailView extends ConsumerWidget {
  const ServarrDetailView({
    super.key,
    required this.item,
    required this.kind,
    required this.torrents,
    required this.onBack,
  });

  final ServarrTitle item;
  final ServarrKind kind;
  final List<ServarrDownload>? torrents;
  final VoidCallback onBack;

  bool get _isSeries => kind == ServarrKind.series;
  String get _key => item.key(kind);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    ref.watch(servarrRequestsProvider); // rebuild on request-state change
    final notifier = ref.read(servarrRequestsProvider.notifier);
    final state = notifier.stateFor(item, kind);

    final torrent = matchTorrent(item.title, torrents);
    final active = torrent != null && !torrent.isPaused;
    final pct = torrent?.percent ?? 0;
    final torrentDownloading = active && pct < 100;
    final downloading = state == ServarrRequestState.grabbed || torrentDownloading;
    final searching =
        state == ServarrRequestState.searching && !torrentDownloading;
    final monitoring =
        state == ServarrRequestState.monitoring && !torrentDownloading;
    final noRelease =
        state == ServarrRequestState.noRelease && !torrentDownloading;
    final searchFailed =
        state == ServarrRequestState.searchFailed && !torrentDownloading;

    final rating = item.rating;
    final runtime = fmtRuntimeFromMinutes(item.runtime);
    final genres = item.genres.where((g) => g.isNotEmpty).take(3).toList();
    final infoLine = <String>[
      if (item.year != null) '${item.year}',
      if (runtime != null) runtime,
      if (item.certification != null && item.certification!.isNotEmpty)
        item.certification!,
      if (_isSeries && item.seasonCount != null)
        '${item.seasonCount} season${item.seasonCount == 1 ? '' : 's'}',
      if (_isSeries && item.network != null && item.network!.isNotEmpty)
        item.network!,
      if (_isSeries && item.status != null && item.status!.isNotEmpty)
        item.status!,
    ];

    return Stack(
      children: [
        SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Positioned.fill(child: _Backdrop(url: item.backdropUrl)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(34, 90, 34, 34),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _Poster(url: item.posterUrl),
                        const SizedBox(width: 26),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isSeries ? 'SERIES' : 'MOVIE',
                                style: AppTheme.mono.copyWith(
                                  fontSize: 12,
                                  color: wp.faint,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.title,
                                style: AppTheme.headlineLarge
                                    .copyWith(color: wp.text),
                              ),
                              const SizedBox(height: 14),
                              _RatingGenres(rating: rating, genres: genres),
                              if (infoLine.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    for (final v in infoLine)
                                      Text(
                                        v,
                                        style: AppTheme.mono.copyWith(
                                          fontSize: 13,
                                          color: wp.dim,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 22),
                              if (_isSeries)
                                ServarrSeasonChooser(
                                  item: item,
                                  onWholeSeriesFallback: () =>
                                      notifier.request(item, kind),
                                )
                              else
                                _MovieActions(
                                  item: item,
                                  torrent: torrent,
                                  active: active,
                                  pct: pct,
                                  downloading: downloading,
                                  searching: searching,
                                  monitoring: monitoring,
                                  noRelease: noRelease,
                                  searchFailed: searchFailed,
                                  state: state,
                                  onDownload: () => notifier.request(item, kind),
                                  onOptions: () => _openOptions(context, ref),
                                  onPickRelease: () =>
                                      _openReleasePicker(context, ref),
                                  onAddSource: () => _openManual(context, ref),
                                  onRemove: () => _remove(context, ref),
                                ),
                              if (!_isSeries && !downloading && !searching) ...[
                                const SizedBox(height: 12),
                                AppButton(
                                  label: 'Add source',
                                  icon: Icons.add,
                                  variant: (noRelease || searchFailed)
                                      ? AppButtonVariant.primary
                                      : AppButtonVariant.secondary,
                                  onPressed: () => _openManual(context, ref),
                                ),
                              ],
                              if (item.overview != null &&
                                  item.overview!.isNotEmpty) ...[
                                const SizedBox(height: 22),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 720),
                                  child: Text(
                                    item.overview!,
                                    maxLines: 6,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.body.copyWith(
                                      color: wp.text.withValues(alpha: 0.85),
                                      fontSize: 15,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
        Positioned(
          top: 18,
          left: 34,
          child: _BackButton(onTap: onBack),
        ),
      ],
    );
  }

  void _openOptions(BuildContext context, WidgetRef ref) {
    showServarrOptionsDialog(
      context,
      item: item,
      kind: kind,
      onAdded: (outcome) =>
          ref.read(servarrRequestsProvider.notifier).applyOutcome(_key, outcome),
    );
  }

  void _openReleasePicker(BuildContext context, WidgetRef ref) {
    showServarrReleasePicker(
      context,
      item: item,
      onGrabbed: () =>
          ref.read(servarrRequestsProvider.notifier).markGrabbed(_key),
      onManual: () => _openManual(context, ref),
    );
  }

  void _openManual(BuildContext context, WidgetRef ref) {
    showServarrManualSourceDialog(
      context,
      item: item,
      kind: kind,
      onSubmitted: () =>
          ref.read(servarrRequestsProvider.notifier).markGrabbed(_key),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirm(
      context,
      title: 'Remove from library?',
      body: 'This deletes the ${_isSeries ? 'series' : 'movie'} and its '
          'downloaded files, and stops it from being auto-redownloaded. This '
          'can\'t be undone.',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!confirmed) return;
    await ref.read(servarrRequestsProvider.notifier).remove(item, kind);
    onBack();
  }
}

class _MovieActions extends StatelessWidget {
  const _MovieActions({
    required this.item,
    required this.torrent,
    required this.active,
    required this.pct,
    required this.downloading,
    required this.searching,
    required this.monitoring,
    required this.noRelease,
    required this.searchFailed,
    required this.state,
    required this.onDownload,
    required this.onOptions,
    required this.onPickRelease,
    required this.onAddSource,
    required this.onRemove,
  });

  final ServarrTitle item;
  final ServarrDownload? torrent;
  final bool active;
  final int pct;
  final bool downloading;
  final bool searching;
  final bool monitoring;
  final bool noRelease;
  final bool searchFailed;
  final ServarrRequestState state;
  final VoidCallback onDownload;
  final VoidCallback onOptions;
  final VoidCallback onPickRelease;
  final VoidCallback onAddSource;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final added = state == ServarrRequestState.added;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (downloading)
          _DownloadingBlock(torrent: torrent, active: active, pct: pct)
        else if (searching)
          _StatusText(
            title: 'Added — finding a release…',
            body: 'It\'s in your library. We\'re looking for a release to '
                'download right now.',
            pulse: true,
          )
        else if (monitoring)
          _StatusText(
            chip: const AppChip(label: 'Added — monitoring', icon: Icons.auto_awesome),
            body: 'It\'s in your library and being monitored — episodes '
                'download on their own as they become available.',
          )
        else if (noRelease)
          _RetryBlock(
            label: 'Try again',
            note: 'No release available right now — try again later.',
            onPressed: onDownload,
          )
        else if (searchFailed)
          _RetryBlock(
            label: 'Retry',
            note: 'Couldn\'t check for a release right now. Please try again.',
            onPressed: onDownload,
          )
        else if (added)
          Row(
            children: [
              const AppChip(label: 'In library', icon: Icons.check),
              const SizedBox(width: AppSpacing.md),
              AppButton(
                label: 'Remove',
                icon: Icons.delete_outline,
                variant: AppButtonVariant.danger,
                onPressed: onRemove,
              ),
            ],
          )
        else
          Row(
            children: [
              AppButton(
                label: state == ServarrRequestState.error
                    ? 'Retry download'
                    : 'Download',
                icon: state == ServarrRequestState.error
                    ? Icons.error_outline
                    : Icons.download,
                variant: state == ServarrRequestState.error
                    ? AppButtonVariant.danger
                    : AppButtonVariant.primary,
                onPressed: onDownload,
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                onPressed: onOptions,
                tooltip: 'Download options',
                icon: Icon(Icons.settings_outlined, color: wp.text),
                style: IconButton.styleFrom(
                  backgroundColor: wp.surface2.withValues(alpha: 0.5),
                  shape: const CircleBorder(),
                  minimumSize: const Size(48, 48),
                ),
              ),
            ],
          ),
        // Secondary: browse every release. Movies only; hidden while a grab is
        // already in flight (downloading/searching).
        if (!downloading && !searching) ...[
          const SizedBox(height: 16),
          AppButton(
            label: added ? 'Choose a release' : 'See all sources',
            icon: Icons.search,
            variant: AppButtonVariant.secondary,
            onPressed: onPickRelease,
          ),
        ],
      ],
    );
  }
}

class _DownloadingBlock extends StatelessWidget {
  const _DownloadingBlock({
    required this.torrent,
    required this.active,
    required this.pct,
  });
  final ServarrDownload? torrent;
  final bool active;
  final int pct;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PulseDot(color: AppColors.live, size: 8),
              const SizedBox(width: 7),
              Text(
                active ? 'Downloading · $pct%' : 'Starting download…',
                style: AppTheme.mono.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: wp.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            child: LinearProgressIndicator(
              value: active ? pct / 100 : null,
              minHeight: 8,
              backgroundColor: wp.text.withValues(alpha: 0.12),
              color: wp.text,
            ),
          ),
          if (active && torrent != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                Text('↓ ${fmtSpeed(torrent!.dlspeed)}',
                    style: AppTheme.mono.copyWith(fontSize: 12.5, color: wp.dim)),
                Text('ETA ${pct >= 100 ? '—' : fmtEta(torrent!.eta)}',
                    style: AppTheme.mono.copyWith(fontSize: 12.5, color: wp.dim)),
                Text('Seeds: ${torrent!.numSeeds} · Peers: ${torrent!.numLeechs}',
                    style: AppTheme.mono.copyWith(fontSize: 12.5, color: wp.dim)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({this.title, this.chip, required this.body, this.pulse = false});
  final String? title;
  final Widget? chip;
  final String body;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chip != null)
            chip!
          else if (title != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pulse) ...[
                  PulseDot(color: wp.text, size: 9),
                  const SizedBox(width: 9),
                ],
                Flexible(
                  child: Text(
                    title!,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: wp.text,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(fontSize: 13.5, color: wp.dim, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _RetryBlock extends StatelessWidget {
  const _RetryBlock({
    required this.label,
    required this.note,
    required this.onPressed,
  });
  final String label;
  final String note;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: label,
            icon: Icons.download,
            variant: AppButtonVariant.primary,
            onPressed: onPressed,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.red,
                    fontWeight: FontWeight.w600,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatingGenres extends StatelessWidget {
  const _RatingGenres({required this.rating, required this.genres});
  final double? rating;
  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    if (rating == null && genres.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star, size: 16, color: wp.text),
              const SizedBox(width: 5),
              Text(
                rating!.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: wp.text,
                ),
              ),
            ],
          ),
        for (final g in genres)
          Text(
            g,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: wp.dim),
          ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (url != null && url!.isNotEmpty)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: AuthedNetworkImage(
              url!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(color: wp.surface),
            ),
          )
        else
          ColoredBox(color: wp.surface),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                wp.bg,
                wp.bg.withValues(alpha: 0.55),
                wp.bg.withValues(alpha: 0.25),
              ],
              stops: const [0.04, 0.48, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xB8000000), Color(0x59000000), Color(0x00000000)],
              stops: [0.0, 0.45, 0.82],
            ),
          ),
        ),
      ],
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Container(
      width: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: wp.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: url != null && url!.isNotEmpty
              ? AuthedNetworkImage(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _fallback(wp),
                )
              : _fallback(wp),
        ),
      ),
    );
  }

  Widget _fallback(WpPalette wp) => ColoredBox(
        color: wp.surface,
        child: Center(child: Icon(Icons.movie_outlined, color: wp.faint)),
      );
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xB80C0F13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left, size: 18, color: Colors.white),
              SizedBox(width: 6),
              Text('Back', style: TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Manual source dialog (magnet / .torrent) ────────────────────────────────

/// Submit a magnet link or a `.torrent` file for a title (mirrors
/// `FindDownload.tsx`'s `ManualSourceDialog`). Adds the title to Radarr/Sonarr
/// first if needed (resolveTargetId), then POSTs `/manual/magnet` (JSON) or
/// uploads the raw `.torrent` body via `ApiClient.manualTorrentUpload`
/// (`application/x-bittorrent`, ≤2 MiB).
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

  bool _magnetMode = true;
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
          _TextField(
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
                      _TextField(
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
                      _TextField(
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
            _TextField(
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

class _TextField extends StatelessWidget {
  const _TextField({
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
