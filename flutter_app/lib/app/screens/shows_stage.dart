// The Shows stage.
//
// The Movies stage, for series. Same backdrop, same copy block, same
// fixed-cursor rail, same motion — see `movies_stage.dart`, which is the
// reference this follows rather than a sibling it negotiates with.
//
//   ┌──────────────────────────────────────────────────┐
//   │  backdrop of the selected show, full bleed       │
//   │                                                  │
//   │  TITLE                                           │
//   │  ★ 8.4 · TV-MA · 2019                            │
//   │  Overview…                                       │
//   │                                                  │
//   │  ▸ small poster rail, cursor pinned to slot 0    │
//   └──────────────────────────────────────────────────┘
//
// The one difference from Movies is what is NOT here: there is no
// Singles ⇄ Collections mode strip, because a show has no equivalent. It is
// removed rather than reduced to a single position — a strip you cannot move
// is a control that lies about being one — and with it go the Up/Down bindings
// that drove it. The aside column stays, empty, because it is what holds the
// copy in the same rectangle the detail page puts it in; collapsing it would
// slide the title sideways on the route transition, which is the exact thing
// `title_layout.dart` exists to stop.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../analog/browse_core.dart';
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

class ShowsStage extends ConsumerStatefulWidget {
  const ShowsStage({super.key});

  @override
  ConsumerState<ShowsStage> createState() => _ShowsStageState();
}

class _ShowsStageState extends ConsumerState<ShowsStage>
    with SingleTickerProviderStateMixin {
  /// The copy's arrival. One controller for the whole block so every line
  /// stays in step; the lines differ by riding different *intervals* of it,
  /// weighted by their type size.
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

  int _selected = 0;

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

  void _activate(List<LibraryItem> items, int index) {
    if (index < 0 || index >= items.length) return;
    final item = items[index];
    if (item.id.isEmpty) return;
    // Straight to the detail page. The poster carries a Hero tag matching the
    // one that page uses, so the artwork flies across the route rather than
    // cutting.
    context.push('/detail/${item.id}');
  }

  /// Shared with the web through app/shared/design/interaction.json: a
  /// threshold, a cooldown between steps, and rejection of the momentum tail.
  final SteppedScrollState _scroll = SteppedScrollState();

  /// When the last step landed, and which way it went. Together these give the
  /// rail its momentum and the copy its travel direction.
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

  /// A trackpad two-finger swipe is pan-zoom, not a scroll event, and this
  /// stage only listened for the latter — so the gesture every laptop user
  /// reaches for first did nothing. Same arithmetic; the delta points the
  /// other way, hence the negation.
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
  ///
  /// Up and Down are deliberately unhandled: on Movies they move the mode
  /// slider, and this stage has none. Returning `ignored` lets them fall
  /// through to whatever else wants them rather than swallowing a key to do
  /// nothing.
  KeyEventResult _onKey(KeyEvent event, List<LibraryItem> items) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _stepSelection(-1, items.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _stepSelection(1, items.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.select:
        _activate(items, _selected);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        // Only meaningful while something is typed: this stage has nothing else
        // to back out of, so an Escape that cleared nothing should fall through
        // rather than be swallowed.
        if (_query.isEmpty) return KeyEventResult.ignored;
        _setQuery('');
        _search.clear();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(apiClientProvider);
    final async = ref.watch(browseByTypeProvider(BrowseTypeFilter.series));

    final items = searchTitles(
      async.valueOrNull ?? const <LibraryItem>[],
      _query,
    );
    final selected = items.isEmpty
        ? null
        : items[_selected.clamp(0, items.length - 1)];

    // The library listing carries no Overview, Genres or ratings — those come
    // from the item record. Falls back to the list row while the record is in
    // flight, so the title never blanks on a step.
    final detailed = selected == null
        ? null
        : ref.watch(itemDetailProvider(selected.id)).valueOrNull ?? selected;

    final media = MediaQuery.of(context);
    final size = stageLayout(media.size.width, media.size.height, false).size;
    final motion = motionProfile(media.disableAnimations);

    // The rail may take up to a bit under half the stage. It is laid over the
    // foot rather than taking a share of the column.
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
                                  loading: async.isLoading,
                                  error: async.hasError
                                      ? 'Could not load this library'
                                      : null,
                                  entry: _copyEntry,
                                  direction: _stepDirection,
                                  velocity: _velocity,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: TitleLayout.columnGap),
                          // Held open on purpose — see the note at the top of
                          // this file. The copy's rectangle is the thing being
                          // preserved, not the strip that used to sit here.
                          // The logo stands in it now, level with the heading.
                          Expanded(
                            flex: TitleLayout.asideFlex,
                            child: Center(
                              child: AsideTitleLogo(
                                itemId: detailed?.id,
                                url: detailed == null
                                    ? null
                                    : titleLogoUrl(api, detailed),
                                maxHeightPx: TitleLayout.asideLogoHeight,
                              ),
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
                      velocity: _velocity,
                      onSelect: (i) => setState(() => _selected = i),
                      onActivate: (i) => _activate(items, i),
                      emptyLabel: switch ((
                        async.isLoading,
                        _query.isNotEmpty,
                      )) {
                        (true, _) => 'Loading…',
                        // The library is not empty — the search is.
                        (false, true) => 'Nothing matches “$_query”',
                        (false, false) => 'No shows in this library',
                      },
                    ),
                  ],
                ),
              ),
              StageSearchOverlay(
                hint: 'Search shows',
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
        // Matches the tag the detail page puts on its poster, which is what
        // makes the artwork fly across the route instead of cutting.
        heroTag: 'poster-${item.id}',
      ),
  ];

  static double? _progressOf(LibraryItem item) {
    final pct = item.userData?.playedPercentage;
    if (pct == null || pct <= 0) return null;
    return (pct / 100).clamp(0.0, 1.0);
  }
}

/// Title, tagline, overview and meta line for the selected show.
class _Details extends StatelessWidget {
  const _Details({
    super.key,
    required this.api,
    required this.item,
    required this.loading,
    required this.error,
    required this.entry,
    required this.direction,
    required this.velocity,
  });

  final ApiClient api;
  final LibraryItem? item;
  final bool loading;
  final String? error;

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
          // Genres lead, as a breadcrumb rather than chips. This is the detail
          // stage's opening line, and putting it anywhere else means the block
          // reorders halfway through the transition.
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
            // The written title. The logo stands in the aside now and flies
            // from there into the detail page's heading.
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

  /// Rating, certificate and year — the facts a series always has, so the line
  /// does not reflow as you step along the rail.
  ///
  /// No runtime: a series' `runTimeTicks` is one episode's, which read as the
  /// length of the whole show and was simply wrong.
  static String _metaLine(LibraryItem item) {
    final parts = <String>[
      if (item.communityRating != null)
        '★ ${item.communityRating!.toStringAsFixed(1)}',
      if ((item.officialRating ?? '').isNotEmpty) item.officialRating!,
      if (item.productionYear != null) '${item.productionYear}',
    ];
    return parts.join('  ·  ').toUpperCase();
  }
}
