import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// Track indices selected on the detail stage, handed to the player/party on
/// Watch (mirrors the web `DetailTrackSelection`).
class DetailTrackSelection {
  const DetailTrackSelection({this.audioStreamIndex, this.subtitleStreamIndex});
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
}

/// The fullscreen cinematic title stage (web `Details`, Library.tsx:801). A
/// full-bleed backdrop under a theme-aware two-axis wash, a glass Back button,
/// and a two-column layout: left copy (genres, title, synopsis, mono metadata,
/// Watch/Resume + track menu) over a right column that is a 2:3 poster for
/// movies or a season selector for series, with a bottom cast strip (movies) or
/// episode dock (series).
///
/// For a series, selecting a season/episode swaps the active title IN PLACE
/// (no navigation) and re-targets Watch — exactly the web `activeId` behavior.
/// [onWatch] carries the play target + selected track indices out to the caller
/// (the detail screen's solo-player route / start-party flow).
class DetailStage extends ConsumerStatefulWidget {
  const DetailStage({
    super.key,
    required this.itemId,
    required this.onWatch,
    required this.onBack,
  });

  final String itemId;
  final void Function(LibraryItem playItem, DetailTrackSelection tracks)
  onWatch;
  final VoidCallback onBack;

  @override
  ConsumerState<DetailStage> createState() => _DetailStageState();
}

class _DetailStageState extends ConsumerState<DetailStage> {
  late String _activeId = widget.itemId;
  LibraryItem? _activeFallback;
  int? _selAudio;
  int? _selSubtitle;
  bool _trackMenuOpen = false;

  /// The id we've already seeded default track selection for, so re-fetches
  /// (e.g. after a subtitle upload) don't clobber a user's choice.
  String? _tracksInitFor;

  void _setActive(LibraryItem item) {
    if (item.id == _activeId) return;
    setState(() {
      _activeId = item.id;
      _activeFallback = item;
      _trackMenuOpen = false;
    });
  }

  void _initTracks(String id, int? audio, int? subtitle) {
    if (_tracksInitFor == id) return;
    setState(() {
      _tracksInitFor = id;
      _selAudio = audio;
      _selSubtitle = subtitle;
    });
  }

  void _selectAudio(int? index) => setState(() => _selAudio = index);
  void _selectSubtitle(int? index) => setState(() => _selSubtitle = index);
  void _toggleTrackMenu() => setState(() => _trackMenuOpen = !_trackMenuOpen);
  void _closeTrackMenu() => setState(() => _trackMenuOpen = false);

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final api = ref.watch(apiClientProvider);
    final rootAsync = ref.watch(itemDetailProvider(widget.itemId));
    final activeAsync = _activeId == widget.itemId
        ? rootAsync
        : ref.watch(itemDetailProvider(_activeId));

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: wp.bg),
        if ((activeAsync.valueOrNull ?? _activeFallback) case final active?)
          _StageBody(
            state: this,
            api: api,
            active: active,
            root: rootAsync.valueOrNull ?? active,
          )
        else
          activeAsync.when(
            loading: () => const _StageSkeleton(),
            error: (e, _) => ErrorState(
              title: 'Failed to load title',
              message: '$e',
              onRetry: () => ref.invalidate(itemDetailProvider(_activeId)),
            ),
            data: (_) => const SizedBox.shrink(),
          ),
        Positioned(
          top: 25,
          left: desktopLeadingControlInset > 0
              ? desktopLeadingControlInset
              : 40,
          child: _GlassBackButton(onTap: widget.onBack),
        ),
      ],
    );
  }
}

class _StageBody extends ConsumerWidget {
  const _StageBody({
    required this.state,
    required this.api,
    required this.active,
    required this.root,
  });

  final _DetailStageState state;
  final ApiClient api;
  final LibraryItem active;
  final LibraryItem root;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootIsSeries = root.type == 'Series';
    final detailSeries = rootIsSeries ? root : null;
    final hero = detailSeries ?? active;
    final isEpisode = active.type == 'Episode';

    // Keep the shell's ambient wash on this title for the return trip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(ambientArtworkIdProvider.notifier);
      if (notifier.state != hero.id) notifier.state = hero.id;
    });

    final seasonsAsync = rootIsSeries
        ? ref.watch(seriesSeasonsProvider(root.id))
        : const AsyncValue<List<SeasonEpisodes>>.data(<SeasonEpisodes>[]);
    final seasonRows = seasonsAsync.valueOrNull ?? const <SeasonEpisodes>[];

    // Playback tracks — movie/episode only.
    PlaybackInfo? playback;
    if (active.type != 'Series') {
      final pb = ref.watch(detailPlaybackProvider(active.id));
      playback = pb.valueOrNull;
      if (playback != null && state._tracksInitFor != active.id) {
        final info = playback;
        final id = active.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!state.mounted) return;
          state._initTracks(id, _defaultAudio(info), _defaultSubtitle(info));
        });
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 860;
        final backdrop = _Backdrop(api: api, heroId: hero.id);
        final copy = _CopyColumn(
          state: state,
          api: api,
          active: active,
          hero: hero,
          detailSeries: detailSeries,
          isEpisode: isEpisode,
          seasonRows: seasonRows,
          playback: playback,
        );

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
                    copy,
                    if (rootIsSeries) ...[
                      const SizedBox(height: 28),
                      _SeasonSelector(
                        state: state,
                        rows: seasonRows,
                        activeId: state._activeId,
                      ),
                      const SizedBox(height: 20),
                      _EpisodeDock(
                        state: state,
                        api: api,
                        rows: seasonRows,
                        activeId: state._activeId,
                        loading: seasonsAsync.isLoading,
                      ),
                    ] else ...[
                      const SizedBox(height: 28),
                      _CastStrip(api: api, people: hero.people),
                    ],
                  ],
                ),
              ),
            ],
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            backdrop,
            const _Wash(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                64,
                80,
                64,
                rootIsSeries ? 260 : 170,
              ),
              child: Row(
                crossAxisAlignment: rootIsSeries
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 92, child: SingleChildScrollView(child: copy)),
                  const SizedBox(width: 80),
                  Expanded(
                    flex: 108,
                    child: rootIsSeries
                        ? _SeasonSelector(
                            state: state,
                            rows: seasonRows,
                            activeId: state._activeId,
                          )
                        : _RightPoster(api: api, item: active),
                  ),
                ],
              ),
            ),
            if (!rootIsSeries)
              Positioned(
                left: 64,
                right: 40,
                bottom: 70,
                child: _CastStrip(api: api, people: hero.people),
              ),
            if (rootIsSeries)
              Positioned(
                left: 64,
                right: 64,
                bottom: 74,
                child: _EpisodeDock(
                  state: state,
                  api: api,
                  rows: seasonRows,
                  activeId: state._activeId,
                  loading: seasonsAsync.isLoading,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CopyColumn extends StatelessWidget {
  const _CopyColumn({
    required this.state,
    required this.api,
    required this.active,
    required this.hero,
    required this.detailSeries,
    required this.isEpisode,
    required this.seasonRows,
    required this.playback,
  });

  final _DetailStageState state;
  final ApiClient api;
  final LibraryItem active;
  final LibraryItem hero;
  final LibraryItem? detailSeries;
  final bool isEpisode;
  final List<SeasonEpisodes> seasonRows;
  final PlaybackInfo? playback;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final rootIsSeries = detailSeries != null;
    final genres = hero.genres.take(3).toList();

    // Play target: series root → first episode; otherwise the active title.
    final firstEpisode =
        seasonRows.isNotEmpty && seasonRows.first.episodes.isNotEmpty
        ? seasonRows.first.episodes.first
        : null;
    final playItem = active.type == 'Series' ? firstEpisode : active;

    final resumeTicks = active.userData?.playbackPositionTicks ?? 0;
    final resumeLabel = resumeTicks > 0 ? _fmtRuntime(resumeTicks) : null;

    final meta = <String>[
      if (hero.communityRating != null)
        '★ ${hero.communityRating!.toStringAsFixed(1)}',
      if (hero.officialRating != null) hero.officialRating!,
      ..._infoLine(active).take(3),
    ];

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
          Text(
            hero.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.displayLarge.copyWith(color: wp.text),
          ),
          if (isEpisode)
            Padding(
              padding: const EdgeInsets.only(top: 13),
              child: Text(
                '${active.seriesName ?? detailSeries?.name ?? ''} · '
                'S${active.parentIndexNumber ?? 0} E${active.indexNumber ?? 0} · ${active.name}',
                style: AppTheme.mono.copyWith(color: wp.dim, fontSize: 11),
              ),
            ),
          if (hero.overview != null)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 590),
                child: Text(
                  hero.overview!,
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
          if (playItem != null) ...[
            const SizedBox(height: 23),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AppButton(
                  label: resumeLabel != null && playItem.id == active.id
                      ? 'Resume $resumeLabel'
                      : rootIsSeries && !isEpisode
                      ? 'Play first episode'
                      : 'Watch now',
                  icon: Icons.play_arrow,
                  variant: AppButtonVariant.primary,
                  onPressed: () {
                    final pass = playItem.id == active.id;
                    state.widget.onWatch(
                      playItem,
                      DetailTrackSelection(
                        audioStreamIndex: pass ? state._selAudio : null,
                        subtitleStreamIndex: pass
                            ? (state._selSubtitle ?? -1)
                            : null,
                      ),
                    );
                  },
                ),
                if (active.type != 'Series') ...[
                  _TrackButton(
                    open: state._trackMenuOpen,
                    onTap: state._toggleTrackMenu,
                  ),
                  DownloadButton(
                    itemId: active.id,
                    title: active.name,
                    runTimeTicks: active.runTimeTicks,
                  ),
                ],
              ],
            ),
            if (state._trackMenuOpen && playback != null) ...[
              const SizedBox(height: 12),
              _TrackMenuPanel(
                itemId: active.id,
                playback: playback!,
                selectedAudio: state._selAudio,
                selectedSubtitle: state._selSubtitle,
                onSelectAudio: state._selectAudio,
                onSelectSubtitle: state._selectSubtitle,
                onClose: state._closeTrackMenu,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.parts});
  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final style = AppTheme.mono.copyWith(
      color: wp.dim,
      fontSize: 10,
      letterSpacing: 0.6,
    );
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
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.api, required this.heroId});
  final ApiClient api;
  final String heroId;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return AuthedNetworkImage(
      api.imageUrl(heroId, type: ImageType.backdrop),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => AuthedNetworkImage(
        api.imageUrl(heroId, type: ImageType.primary),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(color: wp.surface),
      ),
    );
  }
}

/// Theme-aware two-axis wash (styles.css `.library-detail-wash`): a horizontal
/// left-dark → right scrim plus a vertical bottom-dark scrim, both keyed to the
/// theme's page background so light/balanced/dark all read correctly.
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

class _RightPoster extends StatelessWidget {
  const _RightPoster({required this.api, required this.item});
  final ApiClient api;
  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Hero(
            tag: 'poster-${item.id}',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: wp.surface,
                boxShadow: wp.cardShadow,
                border: Border.all(color: wp.line2),
              ),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: AuthedNetworkImage(
                  api.imageUrl(item.id),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(color: wp.surface2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.state,
    required this.rows,
    required this.activeId,
  });
  final _DetailStageState state;
  final List<SeasonEpisodes> rows;
  final String activeId;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final activeSeason = _activeSeason(rows, activeId);
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 230),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < rows.length; i++)
                _SeasonButton(
                  label: rows[i].season.name.isNotEmpty
                      ? rows[i].season.name
                      : 'Season ${i + 1}',
                  active: rows[i].season.id == activeSeason?.season.id,
                  onTap: () {
                    final first = rows[i].episodes.isNotEmpty
                        ? rows[i].episodes.first
                        : null;
                    if (first != null) state._setActive(first);
                  },
                  color: wp.text,
                  faint: wp.faint,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonButton extends StatelessWidget {
  const _SeasonButton({
    required this.label,
    required this.active,
    required this.onTap,
    required this.color,
    required this.faint,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color color;
  final Color faint;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: active ? color : faint,
                  fontSize: active ? 18 : 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 13),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: active ? 34 : 22,
              height: 1,
              color: active ? color : faint,
            ),
          ],
        ),
      ),
    );
  }
}

class _CastStrip extends StatelessWidget {
  const _CastStrip({required this.api, required this.people});
  final ApiClient api;
  final List<Person> people;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final cast = people.where((p) => p.type == 'Actor').take(6).toList();
    if (cast.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 34),
        itemBuilder: (context, i) {
          final p = cast[i];
          return SizedBox(
            width: 190,
            child: Row(
              children: [
                ClipOval(
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: AuthedNetworkImage(
                      api.imageUrl(p.id, type: ImageType.primary),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: wp.surface2,
                        child: Center(
                          child: Text(
                            _initials(p.name),
                            style: TextStyle(
                              color: wp.dim,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: wp.text,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (p.role != null)
                        Text(
                          p.role!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: wp.faint, fontSize: 10),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EpisodeDock extends StatelessWidget {
  const _EpisodeDock({
    required this.state,
    required this.api,
    required this.rows,
    required this.activeId,
    required this.loading,
  });
  final _DetailStageState state;
  final ApiClient api;
  final List<SeasonEpisodes> rows;
  final String activeId;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    if (loading) {
      return Container(
        height: 150,
        decoration: BoxDecoration(
          color: wp.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
      );
    }
    final season = _activeSeason(rows, activeId);
    if (season == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                season.season.name,
                style: TextStyle(
                  color: wp.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${season.episodes.length} episodes',
                style: AppTheme.mono.copyWith(color: wp.faint, fontSize: 12),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 158,
          child: season.episodes.isEmpty
              ? Text(
                  'No episodes available.',
                  style: TextStyle(color: wp.faint, fontSize: 13),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: season.episodes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final ep = season.episodes[i];
                    return _EpisodeCard(
                      api: api,
                      episode: ep,
                      selected: ep.id == activeId,
                      onTap: () => state._setActive(ep),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.api,
    required this.episode,
    required this.selected,
    required this.onTap,
  });
  final ApiClient api;
  final LibraryItem episode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final progress = episode.userData?.playedPercentage;
    return SizedBox(
      width: 210,
      child: GestureDetector(
        onTap: onTap,
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
                        AuthedNetworkImage(
                          api.imageUrl(episode.id, type: ImageType.thumb),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => AuthedNetworkImage(
                            api.imageUrl(episode.id, type: ImageType.primary),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: wp.surface2),
                          ),
                        ),
                        Positioned(
                          left: 11,
                          bottom: 9,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.68),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'E${episode.indexNumber ?? '?'}',
                              style: AppTheme.mono.copyWith(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                        if ((progress ?? 0) > 0)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              value: (progress! / 100).clamp(0, 1),
                              minHeight: 3,
                              backgroundColor: Colors.white24,
                              color: Colors.white,
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
                    '${episode.indexNumber ?? '–'}',
                    style: AppTheme.mono.copyWith(
                      color: wp.faint,
                      fontSize: 11.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      episode.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: wp.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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

class _TrackButton extends StatelessWidget {
  const _TrackButton({required this.open, required this.onTap});
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: 'Audio and subtitles',
      child: Material(
        color: open ? wp.text : wp.surface.withValues(alpha: 0.6),
        shape: CircleBorder(side: BorderSide(color: wp.line2)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              Icons.music_note_outlined,
              size: 18,
              color: open ? wp.bg : wp.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline audio/subtitle track menu — folds the web `DetailTrackMenu`
/// (selection + SRT/VTT upload/delete) into the detail stage. Reads/refreshes
/// via [detailPlaybackProvider]; track selection updates the parent's state so
/// it rides Watch into the player/party.
class _TrackMenuPanel extends ConsumerStatefulWidget {
  const _TrackMenuPanel({
    required this.itemId,
    required this.playback,
    required this.selectedAudio,
    required this.selectedSubtitle,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
    required this.onClose,
  });

  final String itemId;
  final PlaybackInfo playback;
  final int? selectedAudio;
  final int? selectedSubtitle;
  final ValueChanged<int?> onSelectAudio;
  final ValueChanged<int?> onSelectSubtitle;
  final VoidCallback onClose;

  @override
  ConsumerState<_TrackMenuPanel> createState() => _TrackMenuPanelState();
}

class _TrackMenuPanelState extends ConsumerState<_TrackMenuPanel> {
  bool _busy = false;
  String? _error;

  Future<void> _upload() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['srt', 'vtt'],
        withData: true,
      );
      final file = picked?.files.single;
      if (file == null) return;
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final api = ref.read(apiClientProvider);
      final previous = widget.playback.subtitleStreams
          .map((track) => track.index)
          .toSet();
      await api.uploadSubtitle(widget.itemId, _toUtf8(bytes), file.name);

      PlaybackTrack? uploaded;
      for (var attempt = 0; attempt < 6 && uploaded == null; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(Duration(milliseconds: 180 * attempt));
        }
        final refreshed = await api.playbackInfo(widget.itemId);
        for (final track in refreshed.subtitleStreams) {
          if (!previous.contains(track.index)) {
            uploaded = track;
            break;
          }
        }
      }
      ref.invalidate(detailPlaybackProvider(widget.itemId));
      if (uploaded != null) widget.onSelectSubtitle(uploaded.index);
    } catch (e) {
      if (mounted) setState(() => _error = 'Subtitle upload failed: $e');
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
      if (widget.selectedSubtitle == track.index) widget.onSelectSubtitle(null);
      ref.invalidate(detailPlaybackProvider(widget.itemId));
    } catch (e) {
      if (mounted) setState(() => _error = 'Subtitle delete failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final pb = widget.playback;
    return Container(
      width: 430,
      constraints: const BoxConstraints(maxHeight: 460),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: wp.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: wp.line2),
        boxShadow: wp.cardShadow,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Playback tracks',
                    style: TextStyle(
                      color: wp.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                InkWell(
                  onTap: widget.onClose,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 17, color: wp.dim),
                  ),
                ),
              ],
            ),
            if (pb.audioStreams.isNotEmpty) ...[
              _TrackHeading(label: 'Audio'),
              for (var i = 0; i < pb.audioStreams.length; i++)
                _TrackRow(
                  label: _trackLabel(pb.audioStreams[i], 'Audio ${i + 1}'),
                  selected: widget.selectedAudio == pb.audioStreams[i].index,
                  onTap: () => widget.onSelectAudio(pb.audioStreams[i].index),
                ),
              const SizedBox(height: 12),
            ],
            _TrackHeading(label: 'Subtitles'),
            _TrackRow(
              label: 'Off',
              selected:
                  widget.selectedSubtitle == null ||
                  widget.selectedSubtitle! < 0,
              onTap: () => widget.onSelectSubtitle(null),
            ),
            for (var i = 0; i < pb.subtitleStreams.length; i++)
              _TrackRow(
                label: _trackLabel(pb.subtitleStreams[i], 'Subtitle ${i + 1}'),
                selected:
                    widget.selectedSubtitle == pb.subtitleStreams[i].index,
                onTap: () =>
                    widget.onSelectSubtitle(pb.subtitleStreams[i].index),
                onDelete: pb.subtitleStreams[i].isExternal && !_busy
                    ? () => _delete(pb.subtitleStreams[i])
                    : null,
              ),
            const SizedBox(height: 8),
            AppButton(
              label: _busy ? 'Working…' : 'Upload SRT or VTT',
              variant: AppButtonVariant.secondary,
              expand: true,
              onPressed: _busy ? null : _upload,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TrackHeading extends StatelessWidget {
  const _TrackHeading({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.mono.copyWith(
          color: context.wp.faint,
          fontSize: 10.5,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: selected ? wp.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 15,
                      child: selected
                          ? Icon(Icons.check, size: 14, color: wp.text)
                          : null,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? wp.text : wp.dim,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onDelete != null)
            InkWell(
              onTap: onDelete,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.delete_outline, size: 15, color: wp.faint),
              ),
            ),
        ],
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

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  final letters = parts.map((p) => p[0]).join();
  return letters.length > 2
      ? letters.substring(0, 2).toUpperCase()
      : letters.toUpperCase();
}

SeasonEpisodes? _activeSeason(List<SeasonEpisodes> rows, String activeId) {
  for (final row in rows) {
    if (row.episodes.any((e) => e.id == activeId)) return row;
  }
  return rows.isEmpty ? null : rows.first;
}

int? _defaultAudio(PlaybackInfo info) {
  for (final t in info.audioStreams) {
    if (t.isDefault) return t.index;
  }
  return info.audioStreams.isEmpty ? null : info.audioStreams.first.index;
}

int? _defaultSubtitle(PlaybackInfo info) {
  for (final t in info.subtitleStreams) {
    if (t.isDefault || t.isForced) return t.index;
  }
  return null;
}

String _trackLabel(PlaybackTrack t, String fallback) {
  final base = t.displayTitle ?? t.title ?? t.language ?? fallback;
  return [
    base,
    if (t.isDefault) 'Default',
    if (t.isForced) 'Forced',
  ].join(' · ');
}

/// Runtime + premiere + resolution/HDR/size line (web Details.infoLine).
List<String> _infoLine(LibraryItem item) {
  final ms = item.mediaSources.isNotEmpty ? item.mediaSources.first : null;
  MediaStream? video;
  for (final s in ms?.mediaStreams ?? const <MediaStream>[]) {
    if (s.type == 'Video') {
      video = s;
      break;
    }
  }
  final res = video != null ? _resolutionLabel(video.height) : null;
  final videoRange = video?.videoRange;
  final hdr = videoRange != null && videoRange != 'SDR' ? videoRange : null;
  final mediaSize = ms?.size;
  final size = mediaSize != null ? '${(mediaSize / 1000000).round()}M' : null;
  final premiere = item.premiereDate != null
      ? _formatDate(item.premiereDate!)
      : null;
  final runtime = item.runTimeTicks == null
      ? null
      : _fmtRuntime(item.runTimeTicks!);
  return [?runtime, ?premiere, ?res, ?hdr, ?size];
}

String? _fmtRuntime(int ticks) {
  if (ticks <= 0) return null;
  final m = (ticks / 600000000).round();
  final h = m ~/ 60;
  return h > 0 ? '${h}h ${m % 60}m' : '${m}m';
}

String _resolutionLabel(int? height) {
  final h = height ?? 0;
  if (h >= 2160) return '4K';
  if (h >= 1080) return '1080P';
  if (h >= 720) return '720P';
  return h > 0 ? '${h}P' : '?P';
}

String _formatDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

/// Normalise subtitle bytes to UTF-8 so the server (which rejects U+FFFD)
/// accepts them — mirrors the subtitle-manager dialog's `_toUtf8`.
List<int> _toUtf8(List<int> raw) {
  String text;
  try {
    text = utf8.decode(raw);
  } on FormatException {
    text = latin1.decode(raw, allowInvalid: true);
  }
  return utf8.encode(text.replaceAll('\u{FFFD}', ''));
}
