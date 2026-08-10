import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/browse_core.dart';
import '../../analog/chrome/analog_select.dart';
import '../../analog/chrome/chrome.dart';
import '../../analog/stage_layout.dart';
import '../../analog/widgets/analog_copy.dart';
import '../../analog/widgets/analog_poster.dart';
import '../../analog/widgets/analog_rail.dart';
import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/analog_tokens.dart';
import '../../ui/ui.dart';
import '../../ui/widgets/bottom_nav.dart';
import 'title_layout.dart';

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

class _DetailStageState extends ConsumerState<DetailStage>
    with TickerProviderStateMixin {
  /// The page's arrival.
  ///
  /// One controller so the parts land in a deliberate order rather than all
  /// appearing on the same frame. The poster is already handled — it flies in
  /// on a Hero from the rail — so this is for the furniture that has nowhere
  /// to fly from: the cast rises from beneath, the actions come in from the
  /// side, each on its own slice of the clock.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: AnalogMotion.enterMs + AnalogMotion.copySwapMs,
  )..forward();

  /// The copy block's re-arrival when the episode cursor moves.
  ///
  /// Separate from [_enter], which is the page opening once. This one refires
  /// on every step, exactly as the browse stage's does — "episodes follow the
  /// same rule as movies do on the movies tab", and on that tab the text
  /// swaps with the same weighted travel the rail settles with. Starts
  /// settled so the first paint is not an animation from nothing.
  late final AnimationController _copySwap = AnimationController(
    vsync: this,
    duration: AnalogMotion.copySwapMs,
    value: 1,
  );

  /// Which way the cursor last moved, so the copy comes in from that side.
  int _stepDirection = 1;

  @override
  void dispose() {
    _enter.dispose();
    _copySwap.dispose();
    super.dispose();
  }

  late String _activeId = widget.itemId;
  LibraryItem? _activeFallback;
  int? _selAudio;
  int? _selSubtitle;

  /// The id we've already seeded default track selection for, so re-fetches
  /// (e.g. after a subtitle upload) don't clobber a user's choice.
  String? _tracksInitFor;

  void _setActive(LibraryItem item) {
    if (item.id == _activeId) return;
    setState(() {
      _activeId = item.id;
      _activeFallback = item;
    });
    // The copy re-arrives rather than cutting. Fired here rather than at each
    // call site so every route into a new title — key, wheel, click — moves the
    // text the same way.
    _copySwap.forward(from: 0);
  }

  void _initTracks(String id, int? audio, int? subtitle) {
    if (_tracksInitFor == id) return;
    setState(() {
      _tracksInitFor = id;
      _selAudio = audio;
      _selSubtitle = subtitle;
    });
  }

  // ── season / episode navigation ───────────────────────────────────────────
  //
  // Episodes get the Movies stage's input model, whole: the arrows and the
  // wheel work ANYWHERE on the stage, not only over the strip the stills
  // happen to occupy. On Movies the rail is the only thing that scrolls, so a
  // wheel event landing on the backdrop meaning nothing is a dead zone rather
  // than a feature — and that is just as true here.
  //
  // There is exactly ONE wheel region, covering the stage, and it steps
  // episodes. The seasons column deliberately does not take the wheel.
  //
  // It used to, as a nested inner region, and nesting wheel regions is the
  // shape that shipped a double-step — every notch moving two items, a flick
  // moving four. That was arbitrated with [PointerSignalResolver], which does
  // work, but the ambiguity it arbitrated was never wanted: a scroll aimed at
  // the episode rail would step a SEASON the moment the pointer drifted over
  // the column. Seasons change by click and by up/down, both unambiguous, so
  // the region is gone rather than refereed.
  //
  // The arithmetic is [steppedScroll], shared with the web and pinned by the
  // parity suite — never a hand-rolled accumulator, which is what turned a
  // flick into four steps the first time.

  final SteppedScrollState _episodeScroll = SteppedScrollState();

  /// Arrows, from anywhere on the stage — the same map the Movies stage uses.
  /// Left/Right walk the rail, Up/Down move the season slider, Enter plays,
  /// Escape leaves. Bound at the stage rather than inside the rail so they
  /// keep working after a click has moved focus to a season button.
  KeyEventResult _onKey(
    KeyEvent event,
    List<SeasonEpisodes> rows,
    List<LibraryItem> episodes,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _stepEpisode(-1, episodes);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _stepEpisode(1, episodes);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _stepSeason(-1, rows);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _stepSeason(1, rows);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.select:
        _watchEpisode(episodes, _episodeIndex(episodes, _activeId));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        widget.onBack();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// When the last rail step landed. The rail's settle is scaled by this, so a
  /// row being pushed hard carries further past its mark.
  DateTime? _lastStepAt;

  /// 0..1, from the gap since the previous step.
  double get _velocity {
    final last = _lastStepAt;
    if (last == null) return 0;
    final gap = DateTime.now().difference(last).inMilliseconds;
    final fast = AnalogMotion.fastStepMs.inMilliseconds;
    if (gap >= fast) return 0;
    return 1 - gap / fast;
  }

  /// Whichever axis the hardware reported further on. A horizontal rail that
  /// ignored a vertical wheel would read as frozen on every desktop mouse.
  static double _wheelDelta(PointerScrollEvent event) =>
      event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
      ? event.scrollDelta.dx
      : event.scrollDelta.dy;

  /// Route a wheel event to [onStep] through the resolver, so this region and
  /// the other one cannot both claim it.
  void _steppedSignal(
    PointerSignalEvent event,
    SteppedScrollState state,
    void Function(int step) onStep,
  ) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      _stepFrom(
        _wheelDelta(resolved as PointerScrollEvent),
        resolved.timeStamp,
        state,
        onStep,
      );
    });
  }

  /// The trackpad path. A two-finger swipe arrives as pan-zoom rather than a
  /// scroll signal, so it never reached [_steppedSignal] and the rail simply
  /// did not answer it. Not routed through the resolver: that arbitrates
  /// pointer SIGNALS, and a pan-zoom is not one — there is also only a single
  /// wheel region left here, so there is nothing to arbitrate against.
  void _steppedPanZoom(
    PointerPanZoomUpdateEvent event,
    SteppedScrollState state,
    void Function(int step) onStep,
  ) {
    final delta = -event.localPanDelta;
    _stepFrom(
      delta.dx.abs() > delta.dy.abs() ? delta.dx : delta.dy,
      event.timeStamp,
      state,
      onStep,
    );
  }

  void _stepFrom(
    double delta,
    Duration timeStamp,
    SteppedScrollState state,
    void Function(int step) onStep,
  ) {
    final step = steppedScroll(state, delta, timeStamp.inMicroseconds / 1000);
    if (step != 0) onStep(step);
  }

  /// Move the season slider, landing on the new season's first episode — the
  /// season IS the episode that is active, so there is no separate selection to
  /// keep in sync and no way for the two to disagree.
  void _stepSeason(int direction, List<SeasonEpisodes> rows) {
    if (rows.isEmpty) return;
    final current = _activeSeason(rows, _activeId);
    var index = current == null ? 0 : rows.indexOf(current);
    if (index < 0) index = 0;
    final next = (index + direction.sign).clamp(0, rows.length - 1);
    if (next == index) return;
    _stepDirection = direction.sign;
    _selectSeason(rows[next]);
  }

  void _selectSeason(SeasonEpisodes row) {
    if (row.episodes.isEmpty) return;
    _setActive(row.episodes.first);
  }

  /// Move the episode cursor. The rail is fixed-cursor, so this is both "which
  /// episode is selected" and "how far the row has scrolled".
  void _stepEpisode(int direction, List<LibraryItem> episodes) {
    if (episodes.isEmpty) return;
    final current = _episodeIndex(episodes, _activeId);
    _selectEpisode(episodes, current + direction.sign);
  }

  void _selectEpisode(List<LibraryItem> episodes, int index) {
    if (episodes.isEmpty) return;
    final next = index.clamp(0, episodes.length - 1);
    if (episodes[next].id == _activeId) return;
    _stepDirection = next >= _episodeIndex(episodes, _activeId) ? 1 : -1;
    _lastStepAt = DateTime.now();
    _setActive(episodes[next]);
  }

  /// Enter on the cursor plays it. Selection and the active title are the same
  /// thing on a fixed-cursor rail, so the track choices already on screen are
  /// this episode's and ride along.
  void _watchEpisode(List<LibraryItem> episodes, int index) {
    if (index < 0 || index >= episodes.length) return;
    final episode = episodes[index];
    widget.onWatch(
      episode,
      DetailTrackSelection(
        audioStreamIndex: episode.id == _activeId ? _selAudio : null,
        subtitleStreamIndex: episode.id == _activeId
            ? (_selSubtitle ?? -1)
            : null,
      ),
    );
  }

  void _selectAudio(int? index) => setState(() => _selAudio = index);
  void _selectSubtitle(int? index) => setState(() => _selSubtitle = index);

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
          // macOS keeps its traffic lights in the top-left of the CONTENT area,
          // in a band `integratedDesktopChromeHeight` tall. Insetting from the
          // left cleared the lights themselves but left the button's top edge
          // inside that band — visually cramped against them, and sitting in
          // the strip the window uses for dragging. Dropping BELOW the band is
          // what the chat drawer does, for the same reason.
          top: Platform.isMacOS ? integratedDesktopChromeHeight + 8 : 25,
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

    final episodes =
        _activeSeason(seasonRows, state._activeId)?.episodes ??
        const <LibraryItem>[];

    // The seasons column does NOT answer the wheel. It used to, as the inner
    // of two nested wheel regions, and that was a mistake twice over: a
    // scroll aimed at the episodes would step a season the moment the pointer
    // drifted over the column, and the nest needed PointerSignalResolver to
    // stop one gesture counting twice. Seasons change by CLICK and by
    // up/down, which are both unambiguous. Removing the region deletes the
    // ambiguity rather than arbitrating it.
    Widget seasonWheel(Widget child) => child;

    /// The Movies stage's input model, over the whole surface: arrows and the
    /// wheel work wherever the pointer is, because the episode rail is the
    /// only thing here that moves and a dead zone over the backdrop is not a
    /// feature.
    Widget stageInput(Widget child) => Focus(
      autofocus: true,
      onKeyEvent: (_, event) => state._onKey(event, seasonRows, episodes),
      child: Listener(
        onPointerSignal: (e) => state._steppedSignal(
          e,
          state._episodeScroll,
          (step) => state._stepEpisode(step, episodes),
        ),
        onPointerPanZoomUpdate: (e) => state._steppedPanZoom(
          e,
          state._episodeScroll,
          (step) => state._stepEpisode(step, episodes),
        ),
        behavior: HitTestBehavior.opaque,
        child: child,
      ),
    );

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
          final body = Stack(
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
                      seasonWheel(
                        _SeasonStrip(
                          state: state,
                          rows: seasonRows,
                          activeId: state._activeId,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _EpisodeRail(
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
          return rootIsSeries ? stageInput(body) : body;
        }

        final body = Stack(
          fit: StackFit.expand,
          children: [
            backdrop,
            const _Wash(),
            Padding(
              padding: EdgeInsets.fromLTRB(
                TitleLayout.padLeft,
                TitleLayout.padTop,
                TitleLayout.padLeft,
                // One reserve for both, from the browse stage's rail. A series
                // used to hold back a hand-picked 260 and top-align, which put
                // its title in a different place from every other title in the
                // app and made the route in from the rail visibly drop the
                // text. The number a title surface centres against is the
                // browse rail's height, whatever sits under it here.
                copyBottomReserve(MediaQuery.sizeOf(context)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: TitleLayout.copyFlex,
                    // Centred within its column, not flush to the gutter —
                    // matching the browse screen, where the copy sits about
                    // 70px further in. That inset is the last visible
                    // difference between the two surfaces.
                    // Scaled to fit, rather than scrolled or clipped.
                    //
                    // This block went through both wrong answers first. It
                    // used to scroll, which drew a scrollbar down the middle
                    // of the backdrop. Making it non-scrollable removed the
                    // bar and started CUTTING OFF the synopsis and the
                    // Watch/Download row on shorter windows, which is worse —
                    // a control you cannot see is worse than one you have to
                    // scroll to.
                    //
                    // BoxFit.scaleDown is the third answer and the right one:
                    // at a comfortable window nothing changes (it only ever
                    // shrinks, never enlarges), and as the window gets shorter
                    // the whole block — heading, synopsis, meta, buttons —
                    // scales down together and stays complete. Uniform, so the
                    // type hierarchy holds at every size, and automatic, so it
                    // tracks any resolution instead of a list of breakpoints
                    // somebody has to keep extending.
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: TitleLayout.copyMaxWidth,
                          ),
                          child: copy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: TitleLayout.columnGap),
                  Expanded(
                    flex: TitleLayout.asideFlex,
                    child: rootIsSeries
                        ? seasonWheel(
                            Align(
                              alignment: Alignment.centerRight,
                              // Not scrollable — the wheel here steps the
                              // slider. Present only so a long-running series
                              // on a short window clips instead of throwing.
                              child: _NoScrollbar(
                                child: SingleChildScrollView(
                                  physics: const NeverScrollableScrollPhysics(),
                                  child: _SeasonStrip(
                                    state: state,
                                    rows: seasonRows,
                                    activeId: state._activeId,
                                  ),
                                ),
                              ),
                            ),
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
                // Lifted clear of the very bottom edge — the strip is tall
                // enough now that sitting flush against the foot made it read
                // as falling off the stage.
                bottom: 88,
                // Rises from beneath the fold, last of everything on the page:
                // it is the least important thing here and arriving first
                // would pull the eye down before the title has landed.
                child: _Enter(
                  controller: state._enter,
                  slice: const Interval(0.45, 1),
                  from: const Offset(0, 0.7),
                  child: _CastStrip(api: api, people: hero.people),
                ),
              ),
            if (rootIsSeries)
              Positioned(
                // Where the browse rail sits, to the pixel: the same gutters
                // and the same foot reserve. This band is the one the poster
                // rail occupies on the way in, so the episodes have to land in
                // it rather than near it.
                left: TitleLayout.padLeft,
                right: TitleLayout.padLeft,
                bottom: kBottomNavReservedPx,
                // Rises from beneath the fold, last of everything on the page,
                // exactly as the cast strip it replaces did.
                child: _Enter(
                  controller: state._enter,
                  slice: const Interval(0.45, 1),
                  from: const Offset(0, 0.7),
                  child: _EpisodeRail(
                    state: state,
                    api: api,
                    rows: seasonRows,
                    activeId: state._activeId,
                    loading: seasonsAsync.isLoading,
                  ),
                ),
              ),
          ],
        );
        return rootIsSeries ? stageInput(body) : body;
      },
    );
  }
}

/// The poster's flight from the rail: an arc, with elasticity at the end.
///
/// Two of the twelve principles at once. [MaterialRectArcTween] gives the
/// *arc* — real things do not travel in straight lines between two points, and
/// a poster sliding on a diagonal is the tell that it is a rectangle being
/// interpolated rather than an object moving. The curve on top gives the
/// *settle*: it overshoots the destination and comes back, so the poster
/// arrives with weight rather than decelerating perfectly into place.
///
/// The overshoot works because the curve returns values above 1 and the arc
/// tween extrapolates past its end — the same property that makes an
/// overshooting curve illegal on an opacity is what makes it work here.
class _SettleRectTween extends MaterialRectArcTween {
  _SettleRectTween({super.begin, super.end});

  @override
  Rect lerp(double t) => super.lerp(AnalogMotion.settleEase.transform(t));
}

/// One part of the page arriving, on its own slice of the shared entrance.
///
/// Staging, in the twelve-principles sense: the page assembles in an order
/// that leads the eye — title, then actions, then cast — rather than every
/// element appearing together, which reads as a screenshot fading up.
///
/// The travel overshoots and settles, matching the rail; the fade does not,
/// because an overshooting curve returns values above 1 and an opacity above 1
/// is an assertion failure rather than a look.
class _Enter extends StatelessWidget {
  const _Enter({
    required this.controller,
    required this.slice,
    required this.from,
    required this.child,
  });

  final Animation<double> controller;
  final Interval slice;

  /// Start offset as a fraction of the child's own size.
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: controller, curve: slice);
    final settle = CurvedAnimation(
      parent: controller,
      curve: Interval(slice.begin, slice.end, curve: AnalogMotion.settleEase),
    );
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(begin: from, end: Offset.zero).animate(settle),
        child: child,
      ),
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

    // "Episodes follow the same rule as movies do on the movies tab." On that
    // tab the copy is the CURSOR'S title — its name is the heading, its
    // synopsis the prose, its facts the meta run. So here the subject is the
    // selected episode, not the series that contains it, and the series drops
    // to a breadcrumb above the heading exactly as a franchise does when you
    // are looking at one of its parts.
    //
    // Before this the heading was the series at every cursor position and the
    // episode was a mono line underneath, which meant stepping the rail barely
    // changed the page — the opposite of the movies rule.
    final subject = rootIsSeries && isEpisode ? active : hero;

    // An episode carries no genres of its own; they belong to the series and
    // are the same for every episode in it.
    final genres = (subject.genres.isNotEmpty ? subject : hero).genres
        .take(3)
        .toList();

    final seriesCrumb = rootIsSeries && isEpisode ? detailSeries!.name : null;

    // Play target: series root → first episode; otherwise the active title.
    final firstEpisode =
        seasonRows.isNotEmpty && seasonRows.first.episodes.isNotEmpty
        ? seasonRows.first.episodes.first
        : null;
    final playItem = active.type == 'Series' ? firstEpisode : active;

    final resumeTicks = active.userData?.playbackPositionTicks ?? 0;
    final resumeLabel = resumeTicks > 0 ? _fmtRuntime(resumeTicks) : null;

    final rating = subject.communityRating ?? hero.communityRating;
    final certificate = subject.officialRating ?? hero.officialRating;
    final meta = <String>[
      if (rating != null) '★ ${rating.toStringAsFixed(1)}',
      ?certificate,
      // The episode's position, in the meta run rather than as a line of its
      // own — it is a fact about the title like a year or a runtime, and the
      // browse stage keeps all of those on one line.
      if (rootIsSeries && isEpisode)
        'S${active.parentIndexNumber ?? 0} E${active.indexNumber ?? 0}',
      ..._infoLine(active).take(3),
    ];

    // On a series the copy follows the episode cursor, so it re-arrives on
    // every step the way the browse stage's does. Everywhere else the block is
    // fixed for the life of the page and there is nothing to animate: wrapping
    // it anyway would run a transition nothing triggered.
    Widget line(double fontSizePx, Widget child) => rootIsSeries
        ? AnalogWeightedLine(
            entry: state._copySwap,
            direction: state._stepDirection,
            velocity: state._velocity,
            fontSizePx: fontSizePx,
            child: child,
          )
        : child;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: TitleLayout.copyMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The series a chosen episode belongs to, above everything, in the
          // same slot the Movies stage puts a franchise's name.
          if (seriesCrumb != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                seriesCrumb.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TitleType.breadcrumb.copyWith(color: wp.dim),
              ),
            ),
          if (genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: line(
                TitleType.breadcrumb.fontSize ?? 10,
                Text(
                  genres.join('  /  ').toUpperCase(),
                  style: TitleType.breadcrumb.copyWith(color: wp.dim),
                ),
              ),
            ),
          line(
            TitleType.heading.fontSize ?? 52,
            // Long titles step down rather than wrapping to two 52px lines.
            //
            // Episode names here are often two segment titles joined by a
            // slash ("The Snowman Cometh / The Precious, Wonderful, ..."), and
            // at full display size those wrapped, ellipsised, AND pushed Watch
            // now off the bottom of the column — which is what put the copy in
            // a scroll view and a scrollbar down the middle of the stage.
            //
            // Shrinking the type is the fix rather than scrolling, because the
            // block is meant to be read at a glance from across a room: a
            // control you have to scroll to reach is worse than a heading two
            // sizes smaller.
            // The logo is the title as the film sets it, so it takes the
            // heading's slot when there is one. Episodes have no logo of their
            // own and must not borrow the series' — the heading here is the
            // episode's name — so they keep the text and its step-down.
            TitleLogo(
              url: isEpisode ? null : titleLogoUrl(api, subject),
              maxHeightPx: TitleLayout.logoMaxHeight,
              child: Text(
                subject.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TitleType.heading.copyWith(
                  color: wp.text,
                  fontSize: _headingSizeFor(subject.name),
                ),
              ),
            ),
          ),
          // An episode without its own synopsis falls back to the series', so
          // the block never collapses to a bare title mid-rail.
          if ((subject.overview ?? hero.overview) case final overview?)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: TitleLayout.overviewMaxWidth,
                ),
                child: line(
                  TitleType.overview.fontSize ?? 16,
                  Text(
                    overview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TitleType.overview.copyWith(color: wp.dim),
                  ),
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: line(
                TitleType.meta.fontSize ?? 10,
                _MetaLine(parts: meta),
              ),
            ),
          if (playItem != null) ...[
            const SizedBox(height: 23),
            // The actions come in from the left, after the copy above them has
            // settled — they are what the page is *for*, so they arrive last
            // and land on a page that has stopped moving.
            _Enter(
              controller: state._enter,
              slice: const Interval(0.35, 1),
              from: const Offset(-0.18, 0),
              child: Wrap(
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
                      itemId: active.id,
                      playback: playback,
                      selectedAudio: state._selAudio,
                      selectedSubtitle: state._selSubtitle,
                      onSelectAudio: state._selectAudio,
                      onSelectSubtitle: state._selectSubtitle,
                    ),
                    DownloadButton(
                      itemId: active.id,
                      title: active.name,
                      runTimeTicks: active.runTimeTicks,
                    ),
                  ],
                ],
              ),
            ),
            // The menu is an OVERLAY now, opened by the button itself — it used
            // to be an inline child right here, which is why it pushed the copy
            // around when it opened and got clipped by this column.
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
    final style = TitleType.meta.copyWith(color: wp.dim);
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

/// The full-bleed artwork behind the copy.
///
/// Keyed to the SERIES, and deliberately not to the episode cursor.
///
/// The browse stage's backdrop follows its cursor because each movie there has
/// its own, and the artwork changing is what makes the row read as travelling.
/// Episodes are the opposite case: a Jellyfin episode almost never carries a
/// backdrop, so following the cursor meant a request per step that mostly
/// 404'd and fell back — the stage visibly reloading on every notch. The
/// scenery a show is watched against is the show's, and holding it still is
/// what lets the rail be the thing that moves.
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
      // Nudged below centre. Dead centre put the poster's top edge above the
      // copy's, which read as it floating away from the block it belongs to.
      alignment: const Alignment(1, 0.18),
      child: Padding(
        padding: const EdgeInsets.only(right: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Hero(
            tag: 'poster-${item.id}',
            // The poster arrives with the same elasticity the rail settles
            // with: it carries a little past the corner and comes back,
            // instead of gliding to a stop. Flutter takes the flight's shape
            // from the DESTINATION hero, so this is the only place it needs
            // to be declared — the rail's poster does not have to know.
            createRectTween: (begin, end) =>
                _SettleRectTween(begin: begin, end: end),
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

/// The seasons, stacked down the side.
///
/// The same strip the Movies stage puts Singles ⇄ Collections in, down to the
/// type size and the detent — the browse stage is the reference, and two
/// sliders in the same corner of the same layout reading as different controls
/// is the kind of drift `title_layout.dart` exists to stop.
class _SeasonStrip extends StatelessWidget {
  const _SeasonStrip({
    required this.state,
    required this.rows,
    required this.activeId,
  });
  final _DetailStageState state;
  final List<SeasonEpisodes> rows;
  final String activeId;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final active = _activeSeason(rows, activeId);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _SeasonButton(
            label: rows[i].season.name.isNotEmpty
                ? rows[i].season.name
                : 'Season ${i + 1}',
            active: rows[i].season.id == active?.season.id,
            onPressed: () => state._selectSeason(rows[i]),
          ),
          if (i != rows.length - 1) const SizedBox(height: AnalogSpace.smPx),
        ],
      ],
    );
  }
}

class _SeasonButton extends StatelessWidget {
  const _SeasonButton({
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String label;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnalogPressable(
      onPressed: onPressed,
      semanticLabel: label,
      selected: active,
      button: false,
      builder: (context, state) => AnalogFocusRing(
        visible: state.focused,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AnalogSpace.smPx,
            vertical: AnalogSpace.xsPx,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: AnalogType.sansFamily,
                  fontSize: 15,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active || state.lit
                      ? AnalogColor.ink
                      : AnalogColor.inkFaint,
                ),
              ),
              const SizedBox(height: 3),
              // The detent, not a tint: the active position is marked by
              // geometry so it survives a monochrome display.
              AnimatedContainer(
                duration: AnalogMotion.detentMs,
                curve: AnalogMotion.detentEase,
                height: active
                    ? AnalogHairline.activePx
                    : AnalogHairline.idlePx,
                width: active ? 34 : 14,
                color: active ? AnalogColor.ink : AnalogColor.line,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CastStrip extends StatefulWidget {
  const _CastStrip({required this.api, required this.people});
  final ApiClient api;
  final List<Person> people;

  /// The face. Large enough to actually recognise someone, which was the point
  /// of the space under the copy going unused.
  static const double _face = 136;

  /// Card width. Sized to the face rather than to the longest name — the names
  /// sit *under* the portrait now, so a card is as wide as its picture.
  static const double _card = 152;

  static const double _nameSize = 13;
  static const double _roleSize = 12;

  /// Line heights are pinned on the styles below rather than left to the
  /// font's natural metrics, so this sum is exact. Estimating them is what
  /// overflowed the card by 9px: the strip is inside a fixed-height box, and a
  /// height derived from a guess about a typeface is wrong the moment the
  /// typeface resolves to something else.
  static const double _lineHeight = 1.3;
  static const double _gap = 10;

  static double _lineBox(double fontSize) =>
      (fontSize * _lineHeight).ceilToDouble();

  /// Face, gap, name line, role line.
  static double get height =>
      _face + _gap + _lineBox(_nameSize) + _lineBox(_roleSize);

  /// The cast is supporting information, not the subject of the page. It sits
  /// back until looked at rather than competing with the title above it.
  static const double _restOpacity = 0.62;

  @override
  State<_CastStrip> createState() => _CastStripState();
}

class _CastStripState extends State<_CastStrip> {
  final ScrollController _controller = ScrollController();

  /// Where the strip is heading, which is not where it currently is.
  ///
  /// Holding a target separately from the live offset is what makes the glide
  /// continuous: a second wheel notch arriving mid-flight extends the journey
  /// instead of restarting it from wherever the strip happened to have reached.
  double _target = 0;

  /// How far past the raw wheel delta the strip carries. Above 1 it coasts —
  /// this is the "low friction" part; the strip keeps going after the wheel
  /// stops rather than halting under your finger.
  static const double _glideGain = 2.6;

  /// Long enough to read as coasting to a stop. The curve decelerates and does
  /// NOT overshoot: carrying past where the wheel stopped is wanted, springing
  /// back afterwards is not — that reads as the strip being yanked.
  static const Duration _glide = Duration(milliseconds: 460);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A horizontal ListView ignores a vertical mouse wheel — the axes do not
  /// match, so Flutter drops the event and the strip appears frozen on
  /// desktop. Mapping whichever axis the hardware reports onto the one axis
  /// this list has is what actually makes it scrollable with a mouse.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    _glideBy(event.scrollDelta);
  }

  /// The trackpad path: a two-finger swipe is pan-zoom, not a scroll signal.
  /// Without this the cast strip was scrollable with a mouse and inert under
  /// the gesture most people actually use on a laptop.
  void _onPanZoom(PointerPanZoomUpdateEvent event) =>
      _glideBy(-event.localPanDelta);

  void _glideBy(Offset raw) {
    if (!_controller.hasClients) return;
    final delta = raw.dx.abs() > raw.dy.abs() ? raw.dx : raw.dy;

    // Re-anchor if the strip was dragged or has settled, so the target never
    // drifts away from reality.
    if (!_controller.position.isScrollingNotifier.value) {
      _target = _controller.offset;
    }

    _target = (_target + delta * _glideGain).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    if (_target == _controller.offset) return;

    _controller.animateTo(
      _target,
      duration: _glide,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    // Was capped at 6, which silently hid most of a cast.
    final cast = widget.people.where((p) => p.type == 'Actor').toList();
    if (cast.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: _CastStrip.height,
      child: Listener(
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomUpdate: _onPanZoom,
        child: ScrollConfiguration(
          // Let a mouse drag the strip too, not just touch. Desktop users
          // reach for the wheel first but the drag costs nothing to allow.
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
            },
            scrollbars: false,
          ),
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            // Bouncing rather than clamping: a drag carries its momentum and
            // the ends give a little instead of stopping dead against a wall.
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            itemCount: cast.length,
            separatorBuilder: (_, _) => const SizedBox(width: 40),
            itemBuilder: (context, i) {
              final p = cast[i];
              return SizedBox(
                width: _CastStrip._card,
                child: Opacity(
                  opacity: _CastStrip._restOpacity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipOval(
                        child: SizedBox(
                          width: _CastStrip._face,
                          height: _CastStrip._face,
                          child: AuthedNetworkImage(
                            widget.api.imageUrl(p.id, type: ImageType.primary),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: wp.surface2,
                              child: Center(
                                child: Text(
                                  _initials(p.name),
                                  style: TextStyle(
                                    color: wp.dim,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: _CastStrip._gap),
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: wp.text,
                          fontSize: _CastStrip._nameSize,
                          height: _CastStrip._lineHeight,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (p.role != null)
                        Text(
                          p.role!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: wp.faint,
                            fontSize: _CastStrip._roleSize,
                            height: _CastStrip._lineHeight,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The season's episodes, as the Movies rail.
///
/// Not a list of cards with a highlight: the cursor is pinned to the first
/// slot and the row travels under it, with the scale falloff, the trail
/// dimming, the per-slot follow-through and the overshooting settle the browse
/// stage has. "Episodes follow the same rule as movies do on the movies tab",
/// and the cheapest way to guarantee that is to run the same widget over the
/// same arithmetic rather than to re-describe the behaviour here.
///
/// Stills are 16:9 where a poster is 2:3, which is the rail's only parameter —
/// see [AnalogRail.aspectRatio]. Everything else is shared.
class _EpisodeRail extends StatelessWidget {
  const _EpisodeRail({
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
    final season = _activeSeason(rows, activeId);
    final episodes = season?.episodes ?? const <LibraryItem>[];

    final media = MediaQuery.of(context);
    final size = stageLayout(media.size.width, media.size.height, false).size;

    return AnalogRail(
      // The one thing an episode does not share with a poster.
      aspectRatio: AnalogPosterTile.stillAspect,
      maxHeightPx: media.size.height * TitleLayout.railStageShare,
      items: [
        for (final ep in episodes)
          AnalogRailItem(
            id: ep.id,
            label: ep.name,
            subtitle: 'E${ep.indexNumber ?? '–'}',
            // Thumb, not Primary: a still is a wide frame and Primary on an
            // episode is not reliably one. Behind the session either way, so
            // it goes through AuthedNetworkImage inside the tile — a plain
            // Image.network here 401s.
            imageUrl: api.imageUrl(ep.id, type: ImageType.primary),
            placeholderLabel: 'E${ep.indexNumber ?? '–'}',
            progress: _progressOf(ep),
          ),
      ],
      selection: _episodeIndex(episodes, activeId),
      size: size,
      motion: motionProfile(media.disableAnimations),
      velocity: state._velocity,
      // Deliberately NOT autofocus: the stage above owns the arrows so they
      // keep working after a click has moved focus elsewhere, exactly as they
      // do on the Movies stage. Two autofocus nodes in one scope is also a
      // coin toss over which one wins. These stay wired so the rail is still
      // self-sufficient if something ever does focus it.
      onCrossAxis: (direction) => state._stepSeason(direction, rows),
      onEscape: state.widget.onBack,
      onSelect: (i) => state._selectEpisode(episodes, i),
      onActivate: (i) => state._watchEpisode(episodes, i),
      emptyLabel: loading ? 'Loading…' : 'No episodes in this season',
    );
  }

  static double? _progressOf(LibraryItem item) {
    final pct = item.userData?.playedPercentage;
    if (pct == null || pct <= 0) return null;
    return (pct / 100).clamp(0.0, 1.0);
  }
}

/// The audio/subtitle control: a glyph that opens the kit's dropdown.
///
/// This used to be a button plus a 430px panel rendered INLINE in the copy
/// column. Opening it shoved the title and overview around, and the panel
/// inherited the column's clip — so it was cut off at the bottom with nothing
/// able to scroll it. The menu is an overlay now ([showAnalogSelect]), which
/// is the actual fix; everything else here is the same upload/delete logic it
/// always had.
class _TrackButton extends ConsumerStatefulWidget {
  const _TrackButton({
    required this.itemId,
    required this.playback,
    required this.selectedAudio,
    required this.selectedSubtitle,
    required this.onSelectAudio,
    required this.onSelectSubtitle,
  });

  final String itemId;

  /// Null while the probe is in flight — the button stays visible but inert
  /// rather than popping into existence once playback info lands.
  final PlaybackInfo? playback;
  final int? selectedAudio;
  final int? selectedSubtitle;
  final ValueChanged<int?> onSelectAudio;
  final ValueChanged<int?> onSelectSubtitle;

  @override
  ConsumerState<_TrackButton> createState() => _TrackButtonState();
}

class _TrackButtonState extends ConsumerState<_TrackButton> {
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
      final previous =
          widget.playback?.subtitleStreams
              .map((track) => track.index)
              .toSet() ??
          const <int>{};
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

  final GlobalKey _anchor = GlobalKey();

  /// One menu picks from two different lists, so a bare index cannot say which
  /// one was chosen. `(kind, index)` can, and a record is cheaper than a pair
  /// of sealed classes for something that never leaves this file.
  void _open() {
    final pb = widget.playback;
    if (pb == null) return;
    showAnalogSelect<(String, int?)>(
      context: context,
      anchor: _anchor,
      selected: _selectedKey(),
      groups: [
        if (pb.audioStreams.isNotEmpty)
          AnalogChoiceGroup(
            icon: Icons.graphic_eq,
            choices: [
              for (var i = 0; i < pb.audioStreams.length; i++)
                AnalogChoice(
                  value: ('audio', pb.audioStreams[i].index),
                  label: _trackLabel(pb.audioStreams[i], 'Audio ${i + 1}'),
                ),
            ],
          ),
        AnalogChoiceGroup(
          icon: Icons.closed_caption_outlined,
          choices: [
            const AnalogChoice(value: ('sub', null), label: 'Off'),
            for (var i = 0; i < pb.subtitleStreams.length; i++)
              AnalogChoice(
                value: ('sub', pb.subtitleStreams[i].index),
                label: _trackLabel(pb.subtitleStreams[i], 'Subtitle ${i + 1}'),
                onDelete: pb.subtitleStreams[i].isExternal && !_busy
                    ? () => _delete(pb.subtitleStreams[i])
                    : null,
              ),
          ],
        ),
      ],
      footerIcon: Icons.upload_file_outlined,
      footerTooltip: 'Upload a subtitle file (SRT or VTT)',
      onFooter: _busy ? null : _upload,
      onSelected: (choice) {
        if (choice.$1 == 'audio') {
          widget.onSelectAudio(choice.$2);
        } else {
          widget.onSelectSubtitle(choice.$2);
        }
      },
    );
  }

  (String, int?) _selectedKey() {
    final sub = widget.selectedSubtitle;
    return ('sub', sub != null && sub >= 0 ? sub : null);
  }

  @override
  Widget build(BuildContext context) {
    // The upload failure has nowhere to print now that the panel is gone, so
    // it rides the button's tooltip and turns the glyph red — the same
    // treatment the party tray gives a failed action.
    return AnalogIconButton(
      key: _anchor,
      icon: _error != null
          ? Icons.error_outline
          : Icons.closed_caption_outlined,
      tooltip: _error ?? 'Audio and subtitles',
      tone: AnalogIconButtonTone.solid,
      color: _error != null ? AppColors.red : null,
      size: 44,
      iconSize: 20,
      onPressed: widget.playback == null || _busy ? null : _open,
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

/// Where the cursor sits in the season's row.
///
/// Falls back to 0 rather than -1: the active title is the series itself until
/// an episode is picked, and a rail cannot render a negative selection.
int _episodeIndex(List<LibraryItem> episodes, String activeId) {
  for (var i = 0; i < episodes.length; i++) {
    if (episodes[i].id == activeId) return i;
  }
  return 0;
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
  // Jellyfin's displayTitle usually ALREADY ends in "Default"/"Forced", so
  // appending them unconditionally produced "AAC - Stereo - Default · Default".
  // Only add a flag the base has not already said.
  final lower = base.toLowerCase();
  return [
    base,
    if (t.isDefault && !lower.contains('default')) 'Default',
    if (t.isForced && !lower.contains('forced')) 'Forced',
  ].join(' · ');
}

/// Strips the scrollbar a desktop [ScrollBehavior] adds to every Scrollable.
///
/// NeverScrollableScrollPhysics stops the viewport RESPONDING to input; it
/// does not stop the bar being painted. The bar tracks whether content exceeds
/// the viewport, not whether you may scroll it — so a copy column that merely
/// overflows still drew a pale line down the middle of the backdrop, on a
/// surface whose whole premise is that the artwork is the interface.
///
/// The two are separate switches and both are needed: physics for behaviour,
/// this for the chrome.
class _NoScrollbar extends StatelessWidget {
  const _NoScrollbar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: child,
  );
}

/// The display size for a title of [name]'s length.
///
/// Three steps, not a continuous scale: a heading that is a slightly different
/// size on every title reads as sloppy, while three deliberate sizes read as a
/// type ramp. The thresholds are character counts because the constraint is
/// how many lines it takes, and at this width that tracks length closely
/// enough to beat measuring and re-laying out.
double _headingSizeFor(String name) {
  final full = TitleType.heading.fontSize ?? 52;
  if (name.length <= 28) return full;
  if (name.length <= 48) return full * 0.72;
  return full * 0.56;
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
