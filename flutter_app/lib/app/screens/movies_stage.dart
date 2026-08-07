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
import '../../analog/movie_browse.dart';
import '../../analog/stage_layout.dart';
import '../../analog/widgets/analog_rail.dart';
import '../../analog/widgets/analog_stage.dart';
import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/analog_tokens.dart';
import '../../ui/widgets/bottom_nav.dart';
import 'title_layout.dart';

class MoviesStage extends ConsumerStatefulWidget {
  const MoviesStage({super.key});

  @override
  ConsumerState<MoviesStage> createState() => _MoviesStageState();
}

class _MoviesStageState extends ConsumerState<MoviesStage> {
  BrowseMode _mode = BrowseMode.singles;

  /// The franchise we have drilled into, or null at the list level.
  LibraryItem? _collection;

  /// One selection per surface, so switching modes or backing out of a
  /// franchise returns to the title you left rather than to index 0.
  final Map<String, int> _selection = {};

  String get _surfaceKey =>
      _collection == null ? 'movies:${_mode.wireName}' : 'collection:${_collection!.id}';

  int get _selected => _selection[_surfaceKey] ?? 0;
  set _selected(int value) => _selection[_surfaceKey] = value;

  void _setMode(BrowseMode mode) {
    if (mode == _mode && _collection == null) return;
    setState(() {
      _mode = mode;
      // Switching modes leaves any franchise you were inside: a franchise's
      // parts are not something Singles can show.
      _collection = null;
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
        setState(() => _collection = item);
      case PlayActivation(:final itemId):
        // Straight to the detail page. The poster carries a Hero tag matching
        // the one that page already uses, so the artwork flies across the
        // route rather than cutting — the shared element does the work a
        // hand-rolled morph was doing badly.
        context.push('/detail/$itemId');
      case NoActivation():
        break;
    }
  }

  void _back() {
    if (_collection != null) setState(() => _collection = null);
  }

  /// Wheel deltas arrive in bursts; one notch is one step and the remainder is
  /// dropped rather than accumulated into a jump on the next event.
  static const double _wheelThreshold = 24;
  double _wheelAccum = 0;

  void _stepSelection(int direction, int total) {
    if (total <= 0) return;
    final next = (_selected + direction.sign).clamp(0, total - 1);
    if (next == _selected) return;
    setState(() => _selected = next);
  }

  /// Scrolling **anywhere on the stage** drives the rail, not just over it.
  /// The rail is the only thing on this surface that scrolls, so a wheel event
  /// landing on the backdrop meaning nothing was a dead zone, not a feature.
  void _onPointerSignal(PointerSignalEvent event, int total) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dx.abs() > event.scrollDelta.dy.abs()
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    _wheelAccum += delta;
    if (_wheelAccum.abs() < _wheelThreshold) return;
    _stepSelection(_wheelAccum.sign.toInt(), total);
    _wheelAccum = 0;
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
        _back();
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

    final items = async.valueOrNull ?? const <LibraryItem>[];
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
    final size = stageLayout(
      media.size.width,
      media.size.height,
      false,
    ).size;
    final motion = motionProfile(media.disableAnimations);

    // The rail may take up to a bit under half the stage. It is laid over the
    // foot rather than taking a share of the column — see the Stack below.
    final railBudget = media.size.height * 0.40;

    return AnalogStage(
      backdropUrl: selected == null
          ? null
          : api.imageUrl(selected.id, type: ImageType.backdrop),
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _onKey(event, items),
        child: Listener(
          onPointerSignal: (e) => _onPointerSignal(e, items.length),
          // Opaque so a wheel event over the bare backdrop still reaches us:
          // "scrolling anywhere should work" means the whole stage, not the
          // strip of it the posters happen to occupy.
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // The copy sits in exactly the rectangle the detail page puts it
              // in — same insets, same 92/108 split, same vertical centring —
              // so the transition between the two surfaces moves everything
              // except the text.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  TitleLayout.padLeft,
                  TitleLayout.padTop,
                  TitleLayout.padLeft,
                  TitleLayout.padBottom,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: TitleLayout.copyFlex,
                      child: _Details(
                        item: detailed,
                        collection: _collection,
                        loading: async.isLoading,
                        error: async.hasError
                            ? 'Could not load this library'
                            : null,
                        onPlay: selected == null
                            ? null
                            : () => _activate(items, _selected),
                        onBack: _collection == null ? null : _back,
                      ),
                    ),
                    const SizedBox(width: TitleLayout.columnGap),
                    Expanded(
                      flex: TitleLayout.asideFlex,
                      child: _collection == null
                          ? Align(
                              alignment: Alignment.centerRight,
                              child: _ModeStrip(
                                mode: _mode,
                                onChanged: _setMode,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),

              // The rail is laid over the foot of the stage rather than taking
              // a share of the column. If it took a share, the space left for
              // the copy would differ from the detail page's and the centred
              // title would land somewhere else — which is the whole thing
              // this layout exists to prevent.
              Positioned(
                left: TitleLayout.padLeft,
                right: TitleLayout.padLeft,
                bottom: kBottomNavReservedPx,
                child: AnalogRail(
                  maxHeightPx: railBudget,
                  items: _railItems(items, api),
                  selection: _selected.clamp(
                    0,
                    items.isEmpty ? 0 : items.length - 1,
                  ),
                  size: size,
                  motion: motion,
                  onSelect: (i) => setState(() => _selected = i),
                  onActivate: (i) => _activate(items, i),
                  emptyLabel: switch ((async.isLoading, _mode)) {
                    (true, _) => 'Loading…',
                    (false, BrowseMode.collections) =>
                      'No collections in this library',
                    (false, BrowseMode.singles) => 'No movies in this library',
                  },
                ),
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
    required this.item,
    required this.collection,
    required this.loading,
    required this.error,
    required this.onPlay,
    required this.onBack,
  });

  final LibraryItem? item;
  final LibraryItem? collection;
  final bool loading;
  final String? error;
  final VoidCallback? onPlay;
  final VoidCallback? onBack;



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
                  style: _breadcrumbStyle,
                ),
              ],
            ),
            const SizedBox(height: AnalogSpace.mdPx),
          ],

          // Genres lead, as a breadcrumb rather than chips. This is the
          // detail stage's opening line, and putting it anywhere else means
          // the block reorders halfway through the transition.
          if (current != null && current.genres.isNotEmpty) ...[
            Text(
              current.genres.take(3).join('  /  ').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _breadcrumbStyle,
            ),
            const SizedBox(height: AnalogSpace.smPx + 4),
          ],

          Text(
            current?.name ?? (loading ? '' : 'Nothing here'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AnalogType.sansFamily,
              fontSize: 40,
              height: 1.05,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: AnalogColor.ink,
            ),
          ),

          if (current != null) ...[
            if (current.taglines.isNotEmpty) ...[
              const SizedBox(height: AnalogSpace.smPx + 2),
              Text(
                current.taglines.first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AnalogType.sansFamily,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: AnalogColor.inkDim,
                ),
              ),
            ],

            if ((current.overview ?? '').isNotEmpty) ...[
              const SizedBox(height: AnalogSpace.lgPx),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: TitleLayout.overviewMaxWidth,
                ),
                child: Text(
                  current.overview!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AnalogType.sansFamily,
                    fontSize: 14,
                    height: 1.62,
                    color: AnalogColor.inkDim,
                  ),
                ),
              ),
            ],

            // Meta sits UNDER the overview, as one mono run — the rating is
            // part of the line here rather than a separate mark, because that
            // is how the detail stage reads it and the two must not differ.
            const SizedBox(height: AnalogSpace.mdPx + 2),
            Text(
              _metaLine(current),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AnalogType.monoFamily,
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w600,
                color: AnalogColor.inkDim,
              ),
            ),

            const SizedBox(height: AnalogSpace.lgPx),
            if (onPlay != null)
              AnalogButton(
                label: current.type == collectionType
                    ? 'Open collection'
                    : 'Watch now',
                icon: current.type == collectionType
                    ? Icons.folder_open
                    : Icons.play_arrow,
                tone: AnalogButtonTone.primary,
                onPressed: onPlay,
              ),
          ],
        ],
      ),
    );
  }

  static const TextStyle _breadcrumbStyle = TextStyle(
    fontFamily: AnalogType.monoFamily,
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.3,
    color: AnalogColor.inkDim,
  );

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
                height: active ? AnalogHairline.activePx : AnalogHairline.idlePx,
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
