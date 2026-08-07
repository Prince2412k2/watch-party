import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/servarr_provider.dart';
import '../../state/show_source.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/download_poster.dart';
import 'servarr_manual_source.dart';
import 'servarr_options_dialog.dart';
import 'servarr_release_picker.dart';
import 'show_stage.dart';

/// Full-page Discover title detail (mirrors `FindDownload.tsx`'s `DetailView`):
/// a blurred backdrop hero with a theme wash, the 2:3 poster, MOVIE/SERIES
/// eyebrow, large title, rating + genres, mono info line, the acquire action(s),
/// and the overview. Movies get one-tap Download + Options + Release picker +
/// Add source + Remove; a series instead renders the unified [ShowStage]
/// (US-3/FR-012) — see [build]. Rendered in-page by [ServarrScreen] (the
/// bottom nav + profile stay visible), so [onBack] just clears the selection.
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
    // A series gets the unified show stage (US-3/FR-012) instead of this
    // screen's own backdrop/poster/season-chooser layout below — Download
    // takes the place of Watch now. Movies are untouched past this point.
    if (_isSeries) {
      return ShowStage(
        show: ShowRef(
          kind: ShowSourceKind.discover,
          id: '${item.tvdbId ?? ''}',
        ),
        onBack: onBack,
        onWatch: null,
      );
    }

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
      ?runtime,
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
                              // Series never reach here — build() returns the
                              // show stage for them above — so this is always
                              // the movie action row.
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

// Manual-source dialog (magnet / .torrent) moved to servarr_manual_source.dart
// so the show stage can reuse it — see [showServarrManualSourceDialog] there.
