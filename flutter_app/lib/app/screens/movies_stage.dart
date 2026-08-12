// The Movies stage.
//
// "We put the posters in movie selection bottom and make them smaller. The
// backdrop will not be this dark and will show the movie's details in the
// library itself — similar to the show screen, where movies will act like
// episodes. We want to add support for movie collections/franchise: on the
// movies tab there will be two options, singles and collections."
//
// The layout that follows from that:
//
//   ┌──────────────────────────────────────────────────┐
//   │  backdrop of the selected title, full bleed      │
//   │                                                  │
//   │  TITLE                                  Singles  │  <- details on top,
//   │  2019 · PG-13 · 2h 14m                Collections│     modes on the side
//   │  Overview…                                       │
//   │  [ Play ]                                        │
//   │                                                  │
//   │  ▸ small poster rail, cursor pinned to slot 0    │  <- lower, smaller
//   └──────────────────────────────────────────────────┘
//
// Selection moves by click, scroll and buttons. Never by hover: hover is not an
// input on a surface that has to work from a remote and from touch, and a
// pointer resting somewhere is not an intent.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../analog/chrome/chrome.dart';
import '../../analog/browse_core.dart';
import '../../analog/movie_browse.dart';
import '../../analog/stage_layout.dart';
import '../../analog/widgets/analog_copy.dart';
import '../../analog/widgets/analog_rail.dart';
import '../../analog/widgets/analog_stage.dart';
import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/analog_tokens.dart';
import '../../ui/widgets/bottom_nav.dart';
import '../../ui/widgets/title_logo.dart';
import 'stage_search.dart';
import 'title_layout.dart';

class MoviesStage extends ConsumerStatefulWidget {
  const MoviesStage({super.key});

  @override
  ConsumerState<MoviesStage> createState() => _MoviesStageState();
}

class _MoviesStageState extends ConsumerState<MoviesStage>
    with SingleTickerProviderStateMixin {
  /// The copy's arrival. One controller for the whole block so every line
  /// stays in step; the lines differ by riding different *intervals* of it,
  /// weighted by their type size. Separate controllers would drift and there
  /// would be nothing holding the block together.
  late final AnimationController _copyEntry = AnimationController(
    vsync: this,
    duration: AnalogMotion.copySwapMs,
    value: 1,
  );

  @override
  void dispose() {
    _copyEntry.dispose();
    _search.dispose();
    super.dispose();
  }

  /// The search line's text. Held here rather than read back out of the field so
  /// clearing it from either side — the × or Escape — moves one thing.
  final TextEditingController _search = TextEditingController();
  String _query = '';

  void _setQuery(String value) {
    setState(() {
      _query = value;
      // The rail is a different list now, so the cursor cannot mean what it
      // meant a keystroke ago.
      _selected = 0;
    });
    _copyEntry.forward(from: 0);
  }

  /// Drops the query when the surface underneath changes. A filter typed for
  /// one shelf silently hiding most of the next one is how a stage ends up
  /// looking empty for no visible reason.
  void _clearQuery() {
    _search.clear();
    _query = '';
  }

  BrowseMode _mode = BrowseMode.singles;

  /// The franchise we have drilled into, or null at the list level.
  LibraryItem? _collection;

  /// One selection per surface, so switching modes or backing out of a
  /// franchise returns to the title you left rather than to index 0.
  final Map<String, int> _selection = {};

  String get _surfaceKey => _collection == null
      ? 'movies:${_mode.wireName}'
      : 'collection:${_collection!.id}';

  int get _selected => _selection[_surfaceKey] ?? 0;
  set _selected(int value) => _selection[_surfaceKey] = value;

  void _setMode(BrowseMode mode) {
    if (mode == _mode && _collection == null) return;
    setState(() {
      _mode = mode;
      // Switching modes leaves any franchise you were inside: a franchise's
      // parts are not something Singles can show.
      _collection = null;
      _clearQuery();
    });
  }

  void _stepMode(int direction) => _setMode(stepBrowseMode(_mode, direction));

  void _activate(List<LibraryItem> items, int index) {
    if (index < 0 || index >= items.length) return;
    final item = items[index];

    // Driven by the item's type rather than the current mode, so a box set
    // opens wherever it is met and everything else plays — one rule instead of
    // three that have to agree.
    switch (activationFor(id: item.id, name: item.name, type: item.type)) {
      case OpenActivation():
        setState(() {
          _collection = item;
          _clearQuery();
        });
      case PlayActivation(:final itemId):
        // Straight to the detail page. The poster and the title's mark both
        // carry Hero tags matching the ones that page uses, so the artwork
        // flies across the route rather than cutting.
        //
        // The RECORD goes with it, not the rail's row. The library listing
        // asks for Primary, Backdrop and Thumb only, so a row carries no Logo
        // tag at all — seeding the page with one left it with a text heading
        // and nothing for the mark to fly into. The record is already in hand:
        // the aside beside this rail is drawing its logo from it.
        context.push(
          '/detail/$itemId',
          extra: ref.read(itemDetailProvider(item.id)).valueOrNull ?? item,
        );
      case NoActivation():
        break;
    }
  }

  void _back() {
    if (_collection != null) {
      setState(() {
        _collection = null;
        _clearQuery();
      });
    }
  }

  /// Shared with the web through app/shared/design/interaction.json: a
  /// threshold, a cooldown between steps, and rejection of the momentum tail.
  /// Hand-rolling this is what made a flick jump several titles at once.
  final SteppedScrollState _scroll = SteppedScrollState();

  /// When the last step landed, and which way it went. Together these give the
  /// rail its momentum and the copy its travel direction — steps arriving
  /// close together mean the row is being pushed hard.
  DateTime? _lastStepAt;
  int _stepDirection = 1;

  /// 0..1, from the gap since the previous step.
  double get _velocity {
    final last = _lastStepAt;
    if (last == null) return 0;
    final gap = DateTime.now().difference(last).inMilliseconds;
    final fast = AnalogMotion.fastStepMs.inMilliseconds;
    if (gap >= fast) return 0;
    return 1 - gap / fast;
  }

  void _stepSelection(int direction, int total) {
    if (total <= 0) return;
    final next = (_selected + direction.sign).clamp(0, total - 1);
    if (next == _selected) return;
    setState(() {
      _stepDirection = direction.sign;
      _lastStepAt = DateTime.now();
      _selected = next;
    });
    _copyEntry.forward(from: 0);
  }

  /// Scrolling **anywhere on the stage** drives the rail, not just over it.
  /// The rail is the only thing on this surface that scrolls, so a wheel event
  /// landing on the backdrop meaning nothing was a dead zone, not a feature.
  void _onPointerSignal(PointerSignalEvent event, int total) {
    if (event is! PointerScrollEvent) return;
    _applyScroll(event.scrollDelta, event.timeStamp, total);
  }

  /// A trackpad two-finger swipe is NOT a scroll event.
  ///
  /// Flutter reports a mouse wheel as [PointerScrollEvent] and a trackpad
  /// gesture as pan-zoom, and this stage only ever listened for the first —
  /// so the gesture every laptop user reaches for first did nothing at all.
  /// Same arithmetic either way; only the event that carries the delta
  /// differs.
  void _onPanZoom(PointerPanZoomUpdateEvent event, int total) =>
      _applyScroll(-event.localPanDelta, event.timeStamp, total);

  void _applyScroll(Offset delta, Duration timeStamp, int total) {
    final primary = delta.dx.abs() > delta.dy.abs() ? delta.dx : delta.dy;
    final step = steppedScroll(
      _scroll,
      primary,
      timeStamp.inMicroseconds / 1000,
    );
    if (step != 0) _stepSelection(step, total);
  }

  /// Arrows work from anywhere on the stage for the same reason.
  KeyEventResult _onKey(KeyEvent event, List<LibraryItem> items) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _stepSelection(-1, items.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _stepSelection(1, items.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (_collection == null) _stepMode(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (_collection == null) _stepMode(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.select:
        _activate(items, _selected);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.backspace:
        // Escape means "undo the narrowing I just did", innermost first: the
        // search, then the franchise.
        if (_query.isNotEmpty) {
          _setQuery('');
          _search.clear();
        } else {
          _back();
        }
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiClientProvider);

    final AsyncValue<List<LibraryItem>> async = switch ((_collection, _mode)) {
      (final c?, _) => ref.watch(collectionItemsProvider(c.id)),
      (null, BrowseMode.collections) => ref.watch(movieCollectionsProvider),
      (null, BrowseMode.singles) => ref.watch(
        browseByTypeProvider(BrowseTypeFilter.movie),
      ),
    };

    final items = searchTitles(
      async.valueOrNull ?? const <LibraryItem>[],
      _query,
    );
    final selected = items.isEmpty
        ? null
        : items[_selected.clamp(0, items.length - 1)];

    // The library listing carries no Overview, Genres or ratings — those come
    // from the item record. Without this the details block could only ever show
    // a name and a runtime, which is what it did. Falls back to the list row
    // while the record is in flight, so the title never blanks on a step.
    final detailed = selected == null
        ? null
        : ref.watch(itemDetailProvider(selected.id)).valueOrNull ?? selected;

    final media = MediaQuery.of(context);
    final size = stageLayout(media.size.width, media.size.height, false).size;
    final motion = motionProfile(media.disableAnimations);

    // The rail may take up to a bit under half the stage. It is laid over the
    // foot rather than taking a share of the column — see the Stack below.
    final railBudget = media.size.height * TitleLayout.railStageShare;

    return AnalogStage(
      backdropUrl: selected == null
          ? null
          : api.imageUrl(selected.id, type: ImageType.backdrop),
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _onKey(event, items),
        child: Listener(
          onPointerSignal: (e) => _onPointerSignal(e, items.length),
          onPointerPanZoomUpdate: (e) => _onPanZoom(e, items.length),
          // Opaque so a wheel event over the bare backdrop still reaches us:
          // "scrolling anywhere should work" means the whole stage, not the
          // strip of it the posters happen to occupy.
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  TitleLayout.padLeft,
                  TitleLayout.padTop,
                  TitleLayout.padLeft,
                  kBottomNavReservedPx,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The copy takes the room the rail does not, and is centred in
                    // it. A Column rather than a Stack because the two genuinely
                    // compete for height once the posters are large: overlaying
                    // them meant the rail sat on top of the overview, and no
                    // choice of bottom reserve fixes that on a short window.
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: TitleLayout.copyFlex,
                            child: Center(
                              child: SingleChildScrollView(
                                // Never scrollable: the wheel belongs to the rail,
                                // and a scroll view here would swallow it. It is
                                // present only so a window too short for the copy
                                // clips instead of throwing an overflow.
                                physics: const NeverScrollableScrollPhysics(),
                                child: _Details(
                                  key: ValueKey(detailed?.id ?? 'empty'),
                                  api: api,
                                  item: detailed,
                                  collection: _collection,
                                  loading: async.isLoading,
                                  error: async.hasError
                                      ? 'Could not load this library'
                                      : null,
                                  onBack: _collection == null ? null : _back,
                                  // Every line rides this one controller, each on
                                  // an interval weighted by its own type size.
                                  entry: _copyEntry,
                                  direction: _stepDirection,
                                  velocity: _velocity,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: TitleLayout.columnGap),
                          Expanded(
                            flex: TitleLayout.asideFlex,
                            // Stacked rather than stapled into a Column. The
                            // strip is taller than the aside on a short window
                            // and has always relied on getting the full box to
                            // clip inside; a Column handed it a share instead,
                            // and it overflowed the moment the rail grew.
                            child: Stack(
                              children: [
                                // Level with the heading it belongs to.
                                Center(
                                  child: AsideTitleLogo(
                                    itemId: detailed?.id,
                                    url: detailed == null
                                        ? null
                                        : titleLogoUrl(api, detailed),
                                    maxHeightPx: TitleLayout.asideLogoHeight,
                                    widthPx: TitleLayout.logoBoxWidth,
                                  ),
                                ),
                                if (_collection == null)
                                  Align(
                                    alignment: Alignment.topRight,
                                    // Same reason as the copy: on a window
                                    // short enough that this does not fit
                                    // beside the rail, it clips rather than
                                    // throwing. Not scrollable — the wheel
                                    // drives the rail.
                                    child: SingleChildScrollView(
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      child: _ModeStrip(
                                        mode: _mode,
                                        onChanged: _setMode,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: TitleLayout.copyToBandGap),
                    AnalogRail(
                      maxHeightPx: railBudget,
                      items: _railItems(items, api),
                      selection: _selected.clamp(
                        0,
                        items.isEmpty ? 0 : items.length - 1,
                      ),
                      size: size,
                      motion: motion,
                      // The rail has always taken a velocity and this stage has
                      // always computed one for the copy; it just was not handed
                      // over, so every step settled at the same canned speed no
                      // matter how hard the row was pushed.
                      velocity: _velocity,
                      onSelect: (i) => setState(() => _selected = i),
                      onActivate: (i) => _activate(items, i),
                      emptyLabel: switch ((
                        async.isLoading,
                        _query.isNotEmpty,
                        _mode,
                      )) {
                        (true, _, _) => 'Loading…',
                        // The library is not empty — the search is. Saying "no
                        // movies in this library" here would blame the wrong thing.
                        (false, true, _) => 'Nothing matches “$_query”',
                        (false, false, BrowseMode.collections) =>
                          'No collections in this library',
                        (false, false, BrowseMode.singles) =>
                          'No movies in this library',
                      },
                    ),
                  ],
                ),
              ),
              StageSearchOverlay(
                hint: _collection != null
                    ? 'Search ${_collection!.name}'
                    : _mode == BrowseMode.collections
                    ? 'Search collections'
                    : 'Search movies',
                query: _query,
                controller: _search,
                onChanged: _setQuery,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<AnalogRailItem> _railItems(List<LibraryItem> items, ApiClient api) => [
    for (final item in items)
      AnalogRailItem(
        id: item.id,
        label: item.name,
        subtitle: item.productionYear?.toString(),
        imageUrl: api.imageUrl(item.id, tag: item.imageTags?['Primary']),
        progress: _progressOf(item),
        // Matches the tag the detail page already puts on its poster, which is
        // what makes the artwork fly across the route instead of cutting.
        heroTag: 'poster-${item.id}',
      ),
  ];

  static double? _progressOf(LibraryItem item) {
    final pct = item.userData?.playedPercentage;
    if (pct == null || pct <= 0) return null;
    return (pct / 100).clamp(0.0, 1.0);
  }
}

/// Title, meta line and overview for the selected item.
class _Details extends StatelessWidget {
  const _Details({
    super.key,
    required this.api,
    required this.item,
    required this.collection,
    required this.loading,
    required this.error,
    required this.onBack,
    required this.entry,
    required this.direction,
    required this.velocity,
  });

  final ApiClient api;
  final LibraryItem? item;
  final LibraryItem? collection;
  final bool loading;
  final String? error;
  final VoidCallback? onBack;

  /// The block's shared arrival, 0..1.
  final Animation<double> entry;

  /// Which way the rail moved, so the copy comes in from that side.
  final int direction;

  /// 0..1 — how hard the row is being pushed, which sets how far the copy
  /// travels. A fast scroll throws the text as far as the posters.
  final double velocity;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          error!,
          style: const TextStyle(
            fontFamily: AnalogType.sansFamily,
            fontSize: 15,
            color: AnalogColor.statusDanger,
          ),
        ),
      );
    }

    final current = item;
    return ConstrainedBox(
      // The same measure the detail stage holds its column to, so the text
      // block is literally the same shape before and after the transition.
      constraints: const BoxConstraints(maxWidth: TitleLayout.copyMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (collection != null) ...[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnalogIconButton(
                  icon: Icons.arrow_back,
                  tooltip: 'Back to collections',
                  onPressed: onBack,
                ),
                const SizedBox(width: AnalogSpace.smPx),
                Text(
                  collection!.name.toUpperCase(),
                  style: TitleType.breadcrumb.copyWith(
                    color: AnalogColor.inkDim,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AnalogSpace.mdPx),
          ],

          // Genres lead, as a breadcrumb rather than chips. This is the
          // detail stage's opening line, and putting it anywhere else means
          // the block reorders halfway through the transition.
          if (current != null && current.genres.isNotEmpty) ...[
            AnalogWeightedLine(
              entry: entry,
              direction: direction,
              velocity: velocity,
              fontSizePx: TitleType.breadcrumb.fontSize ?? 10,
              child: Text(
                current.genres.take(3).join('  /  ').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TitleType.breadcrumb.copyWith(color: AnalogColor.inkDim),
              ),
            ),
            const SizedBox(height: 14),
          ],

          AnalogWeightedLine(
            entry: entry,
            direction: direction,
            velocity: velocity,
            fontSizePx: TitleType.heading.fontSize ?? 52,
            // The written title, in the app's own face. The logo used to take
            // this slot; it now stands in the aside, where there was nothing
            // but empty stage, and flies from there into the detail page's
            // heading when you open the title.
            child: Text(
              current?.name ?? (loading ? '' : 'Nothing here'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TitleType.heading.copyWith(color: AnalogColor.ink),
            ),
          ),

          if (current != null) ...[
            if (current.taglines.isNotEmpty) ...[
              const SizedBox(height: 13),
              AnalogWeightedLine(
                entry: entry,
                direction: direction,
                velocity: velocity,
                fontSizePx: TitleType.tagline.fontSize ?? 15,
                child: Text(
                  current.taglines.first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TitleType.tagline.copyWith(color: AnalogColor.inkDim),
                ),
              ),
            ],

            if ((current.overview ?? '').isNotEmpty) ...[
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: TitleLayout.overviewMaxWidth,
                ),
                child: AnalogWeightedLine(
                  entry: entry,
                  direction: direction,
                  velocity: velocity,
                  fontSizePx: TitleType.overview.fontSize ?? 16,
                  child: Text(
                    current.overview!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TitleType.overview.copyWith(
                      color: AnalogColor.inkDim,
                    ),
                  ),
                ),
              ),
            ],

            // Meta sits UNDER the overview, as one mono run — the rating is
            // part of the line here rather than a separate mark, because that
            // is how the detail stage reads it and the two must not differ.
            const SizedBox(height: 18),
            AnalogWeightedLine(
              entry: entry,
              direction: direction,
              velocity: velocity,
              fontSizePx: TitleType.meta.fontSize ?? 10,
              child: Text(
                _metaLine(current),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TitleType.meta.copyWith(color: AnalogColor.inkDim),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Year, certificate and runtime — the facts that are the same shape for
  /// every title, so the line does not reflow as you step along the rail.
  static String _metaLine(LibraryItem item) {
    final parts = <String>[
      if (item.communityRating != null)
        '★ ${item.communityRating!.toStringAsFixed(1)}',
      if ((item.officialRating ?? '').isNotEmpty) item.officialRating!,
      if (item.runTimeTicks != null && item.runTimeTicks! > 0)
        _runtime(item.runTimeTicks!),
      if (item.productionYear != null) '${item.productionYear}',
    ];
    return parts.join('  ·  ').toUpperCase();
  }

  static String _runtime(int ticks) {
    final minutes = ticks ~/ 600000000;
    final hours = minutes ~/ 60;
    return hours > 0 ? '${hours}h ${minutes % 60}m' : '${minutes}m';
  }
}

/// Singles ⇄ Collections, stacked down the side.
///
/// Presented the way the season slider is — plain text positions each carrying
/// their own detent rule — rather than as a pill or a segmented control, so the
/// two surfaces read as the same idiom.
class _ModeStrip extends StatelessWidget {
  const _ModeStrip({required this.mode, required this.onChanged});

  final BrowseMode mode;
  final ValueChanged<BrowseMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final candidate in browseModes) ...[
          _ModeButton(
            label: browseModeLabels[candidate]!,
            active: candidate == mode,
            onPressed: () => onChanged(candidate),
          ),
          if (candidate != browseModes.last)
            const SizedBox(height: AnalogSpace.smPx),
        ],
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
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
