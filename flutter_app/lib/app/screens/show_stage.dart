import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/servarr_provider.dart' show fmtRuntimeFromMinutes;
import '../../state/show_source.dart';
import '../../ui/ui.dart';
import 'servarr_manual_source.dart';
import 'servarr_release_picker.dart';

/// One stage for a TV series, mounted by BOTH the library and Discover tabs
/// (US-3/FR-012): backdrop + wash, a copy column that swaps between series and
/// episode copy, a season selector, and an episode row along the bottom.
/// [onWatch] is the only thing that differs by caller — null on Discover,
/// where nothing is playable yet — everything else (season/episode download,
/// the wheel, the context menu) works the same regardless of [ShowRef.kind].
///
/// Modeled closely on `detail_stage.dart`'s `DetailStage`/`_StageBody`: same
/// two-column layout, same wash, same spacing constants. It can't literally
/// reuse that file's private widgets (Dart privacy is per-library), so the
/// backdrop/wash/back-button are re-created here to match.
class ShowStage extends ConsumerStatefulWidget {
  const ShowStage({
    super.key,
    required this.show,
    required this.onBack,
    this.onWatch,
  });

  final ShowRef show;
  final VoidCallback onBack;
  final void Function(ShowEpisode episode)? onWatch;

  @override
  ConsumerState<ShowStage> createState() => _ShowStageState();
}

class _ShowStageState extends ConsumerState<ShowStage> {
  int? _season;
  ShowEpisode? _episode;

  bool _allBusy = false;
  String? _allError;
  List<SeasonOutcome>? _allOutcomes;

  DateTime? _lastSeasonWheel;
  DateTime? _lastEpisodeWheel;

  void _pickSeason(int season) {
    if (season == _season) return;
    setState(() {
      _season = season;
      _episode = null;
    });
  }

  void _pickEpisode(ShowEpisode ep) {
    setState(() {
      _season = ep.seasonNumber;
      _episode = ep;
    });
  }

  // Debounced the same way `poster_shelf.dart`'s `_onPointerSignal` is: a
  // 120ms floor between steps so one trackpad flick moves one season/episode,
  // not four (FR-016/SC-006).
  void _handleSeasonWheel(PointerSignalEvent signal, List<int> seasons) {
    final delta = _wheelStep(signal);
    if (delta == null || seasons.length < 2) return;
    final now = DateTime.now();
    if (_lastSeasonWheel != null &&
        now.difference(_lastSeasonWheel!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastSeasonWheel = now;
    final current = _season ?? seasons.first;
    final idx = seasons.indexOf(current);
    final next = (idx < 0 ? 0 : idx) + delta;
    if (next < 0 || next >= seasons.length) return;
    _pickSeason(seasons[next]);
  }

  void _handleEpisodeWheel(PointerSignalEvent signal, List<ShowEpisode> episodes) {
    final delta = _wheelStep(signal);
    if (delta == null || episodes.isEmpty) return;
    final now = DateTime.now();
    if (_lastEpisodeWheel != null &&
        now.difference(_lastEpisodeWheel!) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastEpisodeWheel = now;
    final currentIdx = _episode == null
        ? -1
        : episodes.indexWhere((e) => e.episodeNumber == _episode!.episodeNumber);
    final next = currentIdx < 0
        ? (delta > 0 ? 0 : episodes.length - 1)
        : (currentIdx + delta).clamp(0, episodes.length - 1);
    _pickEpisode(episodes[next]);
  }

  Future<void> _runAutoAll(ShowStageInfo info) async {
    if (_allBusy || !_downloadable(info)) return;
    setState(() {
      _allBusy = true;
      _allError = null;
      _allOutcomes = null;
    });
    try {
      final outcomes =
          await ref.read(showDownloadProvider.notifier).autoAllSeasons(info);
      if (!mounted) return;
      setState(() {
        _allBusy = false;
        _allOutcomes = outcomes;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _allBusy = false;
        _allError = "Couldn't download all seasons right now. Please try again.";
      });
    }
  }

  void _dismissAllPanel() => setState(() {
    _allOutcomes = null;
    _allError = null;
  });

  /// Downloading needs a Sonarr identity — a real seriesId, or a lookup payload
  /// the picker can shell the series in from. Neither exists when the series has
  /// no Tvdb provider id, or when Sonarr is unconfigured or unreachable; the
  /// download affordances have to be absent rather than tripping
  /// [SeriesReleaseTarget]'s assert on tap.
  static bool _downloadable(ShowStageInfo info) =>
      info.sonarrSeriesId != null || info.sonarrSeriesRaw != null;

  void _openSeasonPicker(BuildContext context, ShowStageInfo info, int season) {
    if (!_downloadable(info)) return;
    showReleasePicker(
      context,
      target: SeriesReleaseTarget(
        seriesTitle: info.title,
        seasonNumber: season,
        seriesId: info.sonarrSeriesId,
        seriesRaw: info.sonarrSeriesRaw,
      ),
      onGrabbed: () => _refreshAfterGrab(season),
      onManual: () => showManualSourceDialog(
        context,
        title: info.title,
        sonarrSeriesId: info.sonarrSeriesId,
        seriesRaw: info.sonarrSeriesRaw,
        seasonNumber: season,
      ),
    );
  }

  void _openEpisodePicker(
    BuildContext context,
    ShowStageInfo info,
    ShowEpisode ep,
  ) {
    if (!_downloadable(info)) return;
    showReleasePicker(
      context,
      target: SeriesReleaseTarget(
        seriesTitle: info.title,
        seasonNumber: ep.seasonNumber,
        episodeNumber: ep.episodeNumber,
        episodeName: ep.name,
        seriesId: info.sonarrSeriesId,
        seriesRaw: info.sonarrSeriesRaw,
      ),
      onGrabbed: () => _refreshAfterGrab(ep.seasonNumber),
      onManual: () => showManualSourceDialog(
        context,
        title: info.title,
        sonarrSeriesId: info.sonarrSeriesId,
        seriesRaw: info.sonarrSeriesRaw,
        seasonNumber: ep.seasonNumber,
        episodeNumber: ep.episodeNumber,
      ),
    );
  }

  void _refreshAfterGrab(int season) {
    ref.invalidate(showInfoProvider(widget.show));
    ref.invalidate(
      showEpisodesProvider(ShowEpisodesRef(show: widget.show, seasonNumber: season)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final infoAsync = ref.watch(showInfoProvider(widget.show));

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: wp.bg),
        infoAsync.when(
          loading: () => const _StageSkeleton(),
          error: (e, _) => ErrorState(
            title: 'Failed to load this show',
            message: '$e',
            onRetry: () => ref.invalidate(showInfoProvider(widget.show)),
          ),
          data: (info) => _StageBody(state: this, info: info),
        ),
        Positioned(
          top: 25,
          left: desktopLeadingControlInset > 0 ? desktopLeadingControlInset : 40,
          child: _GlassBackButton(onTap: widget.onBack),
        ),
      ],
    );
  }
}

/// The wheel only carries a signal above a small deadzone, and only along
/// whichever axis moved further — mirrors `poster_shelf.dart`'s `_onPointerSignal`.
int? _wheelStep(PointerSignalEvent signal) {
  if (signal is! PointerScrollEvent) return null;
  final delta = signal.scrollDelta.dx.abs() > signal.scrollDelta.dy.abs()
      ? signal.scrollDelta.dx
      : signal.scrollDelta.dy;
  if (delta.abs() < 2) return null;
  return delta > 0 ? 1 : -1;
}

class _StageBody extends ConsumerWidget {
  const _StageBody({required this.state, required this.info});

  final _ShowStageState state;
  final ShowStageInfo info;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seasons = info.seasonNumbers;
    final activeSeason = state._season ?? (seasons.isNotEmpty ? seasons.first : null);
    final episodesAsync = activeSeason == null
        ? const AsyncValue<List<ShowEpisode>>.data(<ShowEpisode>[])
        : ref.watch(
            showEpisodesProvider(
              ShowEpisodesRef(show: state.widget.show, seasonNumber: activeSeason),
            ),
          );
    final episodes = episodesAsync.valueOrNull ?? const <ShowEpisode>[];
    final seasonArt = activeSeason == null ? null : _seasonArtUrl(info, activeSeason);
    final heroArt = seasonArt ?? info.backdropUrl ?? info.posterUrl;

    final backdrop = _Backdrop(url: heroArt);
    final copy = _CopyColumn(state: state, info: info, activeSeason: activeSeason);
    final seasonSelector = _SeasonSelector(
      state: state,
      info: info,
      seasons: seasons,
      activeSeason: activeSeason,
    );
    final episodeSection = _EpisodeSection(
      state: state,
      info: info,
      activeSeason: activeSeason,
      episodesAsync: episodesAsync,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 860;

        if (narrow) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: Opacity(opacity: 0.16, child: backdrop)),
              const _Wash(),
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 112, 20, 140),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Listener(
                      onPointerSignal: (s) => state._handleSeasonWheel(s, seasons),
                      child: copy,
                    ),
                    const SizedBox(height: 28),
                    Listener(
                      onPointerSignal: (s) => state._handleSeasonWheel(s, seasons),
                      child: seasonSelector,
                    ),
                    const SizedBox(height: 20),
                    Listener(
                      onPointerSignal: (s) => state._handleEpisodeWheel(s, episodes),
                      child: episodeSection,
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              onPointerSignal: (s) => state._handleSeasonWheel(s, seasons),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  backdrop,
                  const _Wash(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(64, 80, 64, 260),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 92, child: SingleChildScrollView(child: copy)),
                        const SizedBox(width: 80),
                        Expanded(flex: 108, child: seasonSelector),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 64,
              right: 64,
              bottom: 74,
              child: Listener(
                onPointerSignal: (s) => state._handleEpisodeWheel(s, episodes),
                child: episodeSection,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CopyColumn extends StatelessWidget {
  const _CopyColumn({required this.state, required this.info, required this.activeSeason});

  final _ShowStageState state;
  final ShowStageInfo info;
  final int? activeSeason;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final ep = state._episode;
    final genres = info.genres.take(3).toList();
    final runtimeLabel = fmtRuntimeFromMinutes(info.runtime);

    final epRuntimeLabel = ep == null ? null : fmtRuntimeFromMinutes(ep.runtime);
    final meta = ep != null
        ? <String>[
            if (ep.rating != null) '★ ${ep.rating!.toStringAsFixed(1)}',
            ?epRuntimeLabel,
            if (ep.airDate != null) _formatDate(ep.airDate!),
          ]
        : <String>[
            if (info.rating != null) '★ ${info.rating!.toStringAsFixed(1)}',
            if (info.certification != null && info.certification!.isNotEmpty)
              info.certification!,
            if (info.year != null) '${info.year}',
            if (info.network != null && info.network!.isNotEmpty) info.network!,
            ?runtimeLabel,
          ];

    final overview = ep?.overview ?? info.overview;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                genres.join('  /  ').toUpperCase(),
                style: AppTheme.mono.copyWith(
                  color: wp.dim,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.3,
                ),
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  onSecondaryTapUp: (d) =>
                      _showScopeMenu(context, d.globalPosition, info),
                  child: Text(
                    info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.displayLarge.copyWith(color: wp.text),
                  ),
                ),
              ),
              if (_ShowStageState._downloadable(info)) ...[
                const SizedBox(width: 14),
                _WholeSeriesButton(
                  busy: state._allBusy,
                  onTap: () => state._runAutoAll(info),
                ),
              ],
            ],
          ),
          if (ep != null)
            Padding(
              padding: const EdgeInsets.only(top: 13),
              child: Text(
                '${info.title} · S${ep.seasonNumber} E${ep.episodeNumber} · '
                '${ep.name ?? ''}',
                style: AppTheme.mono.copyWith(color: wp.dim, fontSize: 11),
              ),
            ),
          if (overview != null && overview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 590),
                child: Text(
                  overview,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.body.copyWith(color: wp.dim),
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: _MetaLine(parts: meta),
            ),
          if (activeSeason != null) ...[
            const SizedBox(height: 23),
            _HeroActions(state: state, info: info, activeSeason: activeSeason!),
          ],
          if (state._allBusy || state._allOutcomes != null || state._allError != null) ...[
            const SizedBox(height: 18),
            _AllSeasonsPanel(
              busy: state._allBusy,
              error: state._allError,
              outcomes: state._allOutcomes,
              onRetry: () => state._runAutoAll(info),
              onDismiss: state._dismissAllPanel,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroActions extends StatelessWidget {
  const _HeroActions({required this.state, required this.info, required this.activeSeason});

  final _ShowStageState state;
  final ShowStageInfo info;
  final int activeSeason;

  @override
  Widget build(BuildContext context) {
    final ep = state._episode;
    final onWatch = state.widget.onWatch;
    final showWatch = onWatch != null && ep != null && ep.hasFile;
    final seasonLabel = 'Download S${activeSeason.toString().padLeft(2, '0')}';

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Re-tested inline (not via `showWatch`) so the analyzer promotes
        // `ep`/`onWatch` to non-null for the `onPressed` closure below.
        if (onWatch != null && ep != null && ep.hasFile)
          AppButton(
            label: 'Watch now',
            icon: Icons.play_arrow,
            variant: AppButtonVariant.primary,
            onPressed: () => onWatch(ep),
          ),
        if (_ShowStageState._downloadable(info))
          AppButton(
            label: seasonLabel,
            icon: Icons.download,
            variant: showWatch
                ? AppButtonVariant.secondary
                : AppButtonVariant.primary,
            onPressed: () => state._openSeasonPicker(context, info, activeSeason),
          )
        else
          // No Sonarr identity — say why instead of offering a dead button.
          Text(
            'Downloading needs this series matched in Sonarr.',
            style: AppTheme.mono.copyWith(color: context.wp.faint, fontSize: 11),
          ),
      ],
    );
  }
}

class _WholeSeriesButton extends StatelessWidget {
  const _WholeSeriesButton({required this.busy, required this.onTap});
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: 'Download all seasons',
      child: Material(
        color: wp.surface.withValues(alpha: 0.6),
        shape: CircleBorder(side: BorderSide(color: wp.line2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onTap,
          child: SizedBox.square(
            dimension: 44,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(13),
                    child: CircularProgressIndicator(strokeWidth: 2, color: wp.text),
                  )
                : Icon(Icons.playlist_add_check, size: 20, color: wp.text),
          ),
        ),
      ),
    );
  }
}

class _AllSeasonsPanel extends StatelessWidget {
  const _AllSeasonsPanel({
    required this.busy,
    required this.error,
    required this.outcomes,
    required this.onRetry,
    required this.onDismiss,
  });

  final bool busy;
  final String? error;
  final List<SeasonOutcome>? outcomes;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: wp.surface2.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: wp.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'All seasons',
                    style: TextStyle(
                      color: wp.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!busy)
                  InkWell(
                    onTap: onDismiss,
                    child: Icon(Icons.close, size: 15, color: wp.faint),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (busy)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Working through every season…',
                    style: TextStyle(color: wp.dim, fontSize: 12.5),
                  ),
                ],
              )
            else if (error != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
                  const SizedBox(height: 8),
                  AppButton(label: 'Try again', icon: Icons.refresh, onPressed: onRetry),
                ],
              )
            else
              for (final o in outcomes ?? const <SeasonOutcome>[])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        o.route == SeasonRoute.none
                            ? Icons.remove_circle_outline
                            : Icons.check_circle,
                        size: 14,
                        color: o.route == SeasonRoute.none ? wp.faint : AppColors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Season ${o.seasonNumber}',
                        style: TextStyle(
                          color: wp.text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _routeLabel(o),
                          style: TextStyle(color: wp.faint, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _routeLabel(SeasonOutcome o) {
    switch (o.route) {
      case SeasonRoute.season:
        return 'Season pack';
      case SeasonRoute.episodes:
        return '${o.grabbed} episode${o.grabbed == 1 ? '' : 's'}';
      case SeasonRoute.none:
        // A season that could not be searched at all is not the same as one
        // that was searched and had nothing (FR-018) — the state layer sets
        // `error` only in the former case.
        if (o.error != null) return "Couldn't search: ${o.error}";
        return o.missing.isEmpty ? 'Already complete' : 'No release found';
    }
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.parts});
  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final style = AppTheme.mono.copyWith(color: wp.dim, fontSize: 10, letterSpacing: 0.6);
    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Container(
              width: 2,
              height: 2,
              decoration: BoxDecoration(color: wp.dim, shape: BoxShape.circle),
            ),
          ),
        );
      }
      children.add(Text(parts[i].toUpperCase(), style: style));
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: children);
  }
}

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.state,
    required this.info,
    required this.seasons,
    required this.activeSeason,
  });

  final _ShowStageState state;
  final ShowStageInfo info;
  final List<int> seasons;
  final int? activeSeason;

  /// Opacity falls 33% per step away from the selection, so the third neighbour
  /// is already gone — the list reads as a wheel with the selected season at its
  /// centre rather than a scrolling column with a highlight.
  static const _fadePerStep = 0.33;

  /// How many rows either side are worth building at all (the rest are
  /// invisible by the rule above).
  static const _visibleSteps = 3;

  @override
  Widget build(BuildContext context) {
    final active = activeSeason;
    final centre = active == null ? 0 : seasons.indexOf(active);
    if (centre < 0) return const SizedBox.shrink();

    // Rendering a window centred on the selection keeps it optically fixed
    // without a scroll controller chasing it.
    final first = (centre - _visibleSteps).clamp(0, seasons.length - 1);
    final last = (centre + _visibleSteps).clamp(0, seasons.length - 1);

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = first; i <= last; i++)
                _SeasonRow(
                  key: ValueKey(seasons[i]),
                  label: seasons[i] == 0 ? 'Specials' : 'Season ${seasons[i]}',
                  distance: (i - centre).abs(),
                  fade: 1 - _fadePerStep * (i - centre).abs(),
                  onTap: () => state._pickSeason(seasons[i]),
                  onSecondaryTap: (pos) => _showScopeMenu(
                    context,
                    pos,
                    info,
                    seasonNumber: seasons[i],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonRow extends StatelessWidget {
  const _SeasonRow({
    super.key,
    required this.label,
    required this.distance,
    required this.fade,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final String label;
  final int distance;
  final double fade;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final selected = distance == 0;
    final opacity = fade.clamp(0.0, 1.0);
    // Type scale rather than a Transform: scaling text blurs it, and the rows
    // need to reflow so the column stays tight as the selection moves.
    final size = selected ? 26.0 : (19.0 - distance * 2).clamp(12.0, 19.0);

    return IgnorePointer(
      ignoring: opacity < 0.05,
      child: AnimatedOpacity(
        duration: AppMotion.hover,
        curve: AppMotion.standard,
        opacity: opacity,
        child: GestureDetector(
          onSecondaryTapUp: (d) => onSecondaryTap(d.globalPosition),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: selected ? 7 : 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: AppMotion.hover,
                      curve: AppMotion.standard,
                      style: TextStyle(
                        color: wp.text,
                        fontSize: size,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        height: 1.1,
                      ),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  AnimatedContainer(
                    duration: AppMotion.hover,
                    curve: AppMotion.standard,
                    width: selected ? 40 : 22,
                    height: 1,
                    color: wp.text,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodeSection extends StatelessWidget {
  const _EpisodeSection({
    required this.state,
    required this.info,
    required this.activeSeason,
    required this.episodesAsync,
  });

  final _ShowStageState state;
  final ShowStageInfo info;
  final int? activeSeason;
  final AsyncValue<List<ShowEpisode>> episodesAsync;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    if (activeSeason == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            activeSeason == 0 ? 'Specials' : 'Season $activeSeason',
            style: TextStyle(color: wp.text, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        episodesAsync.when(
          // Only the actual card row gets a fixed height — an error or empty
          // message must be free to size itself, or it clips (FR-018: a
          // terminal state still has to be fully visible, not squeezed).
          loading: () => SizedBox(
            height: 172,
            child: Row(
              children: List.generate(
                4,
                (i) => const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: LoadingSkeleton(width: 210, height: 158),
                ),
              ),
            ),
          ),
          error: (e, _) => ErrorState(
            title: "Couldn't load episodes",
            message: '$e',
            onRetry: () => state.ref.invalidate(
              showEpisodesProvider(
                ShowEpisodesRef(show: state.widget.show, seasonNumber: activeSeason!),
              ),
            ),
          ),
          data: (episodes) => episodes.isEmpty
              ? const EmptyState(
                  title: 'No episodes for this season yet',
                  icon: Icons.movie_outlined,
                )
              : SizedBox(
                  height: 172,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: episodes.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final ep = episodes[i];
                      return _EpisodeCard(
                        episode: ep,
                        selected: state._episode?.episodeNumber == ep.episodeNumber &&
                            state._episode?.seasonNumber == ep.seasonNumber,
                        onTap: () => state._pickEpisode(ep),
                        onDownload: _ShowStageState._downloadable(info)
                            ? () => state._openEpisodePicker(context, info, ep)
                            : null,
                        onSecondaryTap: (pos) => _showScopeMenu(
                          context,
                          pos,
                          info,
                          seasonNumber: ep.seasonNumber,
                          episodeNumber: ep.episodeNumber,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.episode,
    required this.selected,
    required this.onTap,
    required this.onDownload,
    required this.onSecondaryTap,
  });
  final ShowEpisode episode;
  final bool selected;
  final VoidCallback onTap;
  /// Null when there is no download path for this series at all.
  final VoidCallback? onDownload;
  final void Function(Offset globalPosition) onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return SizedBox(
      width: 210,
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapUp: (d) => onSecondaryTap(d.globalPosition),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected ? wp.text : Colors.transparent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        episode.still != null && episode.still!.isNotEmpty
                            ? AuthedNetworkImage(
                                episode.still!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => ColoredBox(color: wp.surface2),
                              )
                            : ColoredBox(color: wp.surface2),
                        Positioned(
                          left: 11,
                          bottom: 9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.68),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'E${episode.episodeNumber}',
                              style: AppTheme.mono.copyWith(color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                        if (!episode.hasFile && onDownload != null)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Material(
                              color: Colors.black.withValues(alpha: 0.62),
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: onDownload,
                                child: const SizedBox.square(
                                  dimension: 30,
                                  child: Icon(Icons.download, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${episode.episodeNumber}',
                    style: AppTheme.mono.copyWith(color: wp.faint, fontSize: 11.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      episode.name ?? 'Episode ${episode.episodeNumber}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // FR-015/SC-007: noticeably larger than the library
                      // stage's previous 11px episode-name text.
                      style: TextStyle(color: wp.text, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    if (url == null || url!.isEmpty) return ColoredBox(color: wp.surface);
    return AuthedNetworkImage(
      url!,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(color: wp.surface),
    );
  }
}

/// Theme-aware two-axis wash — same gradients as `detail_stage.dart`'s
/// `_Wash` (styles.css `.library-detail-wash`), re-created here because Dart
/// privacy keeps that class out of reach from this file.
class _Wash extends StatelessWidget {
  const _Wash();

  @override
  Widget build(BuildContext context) {
    final bg = context.wp.bg;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                stops: const [0.0, 0.38, 0.70, 1.0],
                colors: [
                  bg.withValues(alpha: 0.92),
                  bg.withValues(alpha: 0.72),
                  bg.withValues(alpha: 0.12),
                  bg.withValues(alpha: 0.42),
                ],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                stops: const [0.0, 0.46],
                colors: [bg.withValues(alpha: 0.9), Colors.transparent],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassBackButton extends StatelessWidget {
  const _GlassBackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Material(
      color: wp.surface.withValues(alpha: 0.72),
      shape: CircleBorder(side: BorderSide(color: wp.line2)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: 40,
          child: Icon(Icons.chevron_left, size: 22, color: wp.text),
        ),
      ),
    );
  }
}

class _StageSkeleton extends StatelessWidget {
  const _StageSkeleton();

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return DecoratedBox(
      decoration: BoxDecoration(color: wp.surface),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(64, 120, 64, 64),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Spacer(),
            LoadingSkeleton(width: 160, height: 14),
            SizedBox(height: 16),
            LoadingSkeleton(width: 420, height: 52),
            SizedBox(height: 20),
            LoadingSkeleton(width: 520, height: 60),
            SizedBox(height: 24),
            LoadingSkeleton(width: 180, height: 44),
            Spacer(),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Best-effort season poster lookup from the raw Sonarr series payload
/// (FR-017) — Sonarr's `seasons[].images[]` when the series is in the
/// library. Absent for a Discover series not yet added, or any shape that
/// doesn't carry per-season art; both fall back to the series backdrop.
String? _seasonArtUrl(ShowStageInfo info, int season) {
  final seasons = info.sonarrSeriesRaw?['seasons'];
  if (seasons is! List) return null;
  for (final s in seasons) {
    if (s is! Map) continue;
    if ((s['seasonNumber'] as num?)?.toInt() != season) continue;
    final images = s['images'];
    if (images is! List) return null;
    for (final img in images) {
      if (img is! Map) continue;
      final url = img['remoteUrl'] ?? img['url'];
      if (url is String && url.isNotEmpty) return url;
    }
  }
  return null;
}

Future<void> _showScopeMenu(
  BuildContext context,
  Offset globalPosition,
  ShowStageInfo info, {
  int? seasonNumber,
  int? episodeNumber,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final chosen = await showMenu<bool>(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    ),
    // The value IS the choice — it preselects the dialog's mode, so the two
    // entries do different things rather than both landing on magnet.
    items: const [
      PopupMenuItem<bool>(value: false, child: Text('Upload .torrent file…')),
      PopupMenuItem<bool>(value: true, child: Text('Paste magnet link…')),
    ],
  );
  if (chosen == null || !context.mounted) return;
  await showManualSourceDialog(
    context,
    title: info.title,
    sonarrSeriesId: info.sonarrSeriesId,
    seriesRaw: info.sonarrSeriesRaw,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    magnetFirst: chosen,
  );
}

String _formatDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
