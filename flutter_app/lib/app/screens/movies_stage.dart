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
import '../../analog/movie_rail.dart';
import '../../analog/stage_layout.dart';
import '../../analog/widgets/analog_poster.dart';
import '../../analog/widgets/analog_rail.dart';
import '../../analog/widgets/analog_stage.dart';
import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/analog_tokens.dart';
import '../../ui/widgets/bottom_nav.dart';
import 'movies_detail_layer.dart';

class MoviesStage extends ConsumerStatefulWidget {
  const MoviesStage({super.key});

  @override
  ConsumerState<MoviesStage> createState() => _MoviesStageState();
}

class _MoviesStageState extends ConsumerState<MoviesStage>
    with SingleTickerProviderStateMixin {
  BrowseMode _mode = BrowseMode.singles;

  /// Browse (0) ⇄ selected (1). One controller drives every part of the move,
  /// so nothing can drift out of step with the poster.
  late final AnimationController _detail = AnimationController(
    vsync: this,
    duration: AnalogMotion.enterMs + AnalogMotion.chromeFadeMs,
    reverseDuration: AnalogMotion.exitMs,
  );

  bool get _open => _detail.value > 0;

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
    _collapse();
    setState(() {
      _mode = mode;
      // Switching modes leaves any franchise you were inside: a franchise's
      // parts are not something Singles can show.
      _collection = null;
    });
  }

  void _stepMode(int direction) => _setMode(stepBrowseMode(_mode, direction));

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  /// Leaving the surface under the selection — a different mode, a different
  /// franchise, a step along the rail — has to close it, or the expanded state
  /// would be describing a title that is no longer selected.
  void _collapse() {
    if (_detail.value != 0) _detail.reverse();
  }

  void _activate(List<LibraryItem> items, int index) {
    if (index < 0 || index >= items.length) return;
    final item = items[index];

    // Driven by the item's type rather than the current mode, so a box set
    // opens wherever it is met and everything else plays — one rule instead of
    // three that have to agree.
    switch (activationFor(id: item.id, name: item.name, type: item.type)) {
      case OpenActivation():
        _detail.value = 0;
        setState(() => _collection = item);
      case PlayActivation():
        // Deliberately not a route. The expanded view is this same widget tree
        // in another configuration, which is the only way the heading and the
        // overview can stay put while the poster flies.
        _detail.forward();
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
    _collapse();
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
        if (_open) {
          _detail.reverse();
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

    final gutter = size == StageSize.phone
        ? AnalogSpace.stageGutterPhonePx
        : AnalogSpace.stageGutterPx;
    final bottomPad = AnalogSpace.xlPx + kBottomNavReservedPx;
    final railBudget = media.size.height * 0.40;

    // The rail's own geometry, computed here as well so the flying poster
    // starts exactly on the slot it is leaving. Same function the rail calls.
    final railWidth = media.size.width - gutter * 2;
    final metrics = analogRailMetrics(
      usableWidthPx: railWidth,
      maxHeightPx: railBudget,
      size: size,
      subtitle: true,
    );
    final railHeight = analogRailHeight(metrics.posterWidthPx, subtitle: true);
    final selectedWidth = metrics.posterWidthPx * kRailSelectedScale;
    final trail = railTrailPx(metrics.posterWidthPx, metrics.gapPx);

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
          child: AnimatedBuilder(
            animation: _detail,
            builder: (context, _) {
              final t = _detail.value;
              final railT = MoviesDetailStagger.rail.transform(t);
              final posterT = MoviesDetailStagger.poster.transform(t);
              final actionsT = MoviesDetailStagger.actions.transform(t);
              final castT = MoviesDetailStagger.cast.transform(t);

              // Where the poster starts: its slot in the rail, artwork only.
              final artHeight = AnalogPosterTile.artHeightFor(selectedWidth);
              final from = Rect.fromLTWH(
                gutter + trail,
                media.size.height -
                    bottomPad -
                    AnalogPosterTile.captionHeight(subtitle: true) -
                    artHeight,
                selectedWidth,
                artHeight,
              );

              // Where it lands: bigger, left of the details, sitting above the
              // cast row.
              final heroWidth = (media.size.width * 0.17).clamp(150.0, 260.0);
              final heroHeight = AnalogPosterTile.artHeightFor(heroWidth);
              final castHeight = media.size.height * 0.20;
              final to = Rect.fromLTWH(
                gutter,
                media.size.height - bottomPad - castHeight - heroHeight -
                    AnalogSpace.xlPx,
                heroWidth,
                heroHeight,
              );

              final posterRect = Rect.lerp(from, to, posterT)!;

              return Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      AnalogSpace.xlPx,
                      gutter,
                      bottomPad,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // The details make room for the poster as it
                              // arrives. The text itself does not change size
                              // or weight — it is the same widget throughout,
                              // which is the whole point of the 1:1 layout.
                              SizedBox(
                                width:
                                    (posterRect.width + AnalogSpace.xlPx) *
                                    posterT,
                              ),
                              Expanded(
                                child: _Details(
                                  item: detailed,
                                  collection: _collection,
                                  loading: async.isLoading,
                                  error: async.hasError
                                      ? 'Could not load this library'
                                      : null,
                                  // The Play button belongs to the action bar
                                  // once expanded, so it fades out as that
                                  // slides in rather than being shown twice.
                                  showPlay: t < 0.01,
                                  // Kept in the details column rather than
                                  // positioned absolutely: the poster's rect
                                  // is over that corner of the stage, and an
                                  // absolute bar simply rendered underneath it.
                                  actionsProgress: actionsT,
                                  onPlay: selected == null
                                      ? null
                                      : () => _activate(items, _selected),
                                  onOpen: detailed == null
                                      ? null
                                      : () => context.push('/detail/${detailed.id}'),
                                  onCollapse: () => _detail.reverse(),
                                  onBack: _collection == null ? null : _back,
                                ),
                              ),
                              const SizedBox(width: AnalogSpace.xlPx),
                              if (_collection == null)
                                Opacity(
                                  opacity: 1 - railT,
                                  child: _ModeStrip(
                                    mode: _mode,
                                    onChanged: _setMode,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AnalogSpace.lgPx),
                        // The rail drops away and fades. It is what the poster
                        // is leaving, so it clears out first.
                        SizedBox(
                          height: railHeight,
                          child: railT >= 1
                              ? const SizedBox.shrink()
                              : Transform.translate(
                                  offset: Offset(0, railHeight * railT),
                                  child: Opacity(
                                    opacity: 1 - railT,
                                    child: AnalogRail(
                                      maxHeightPx: railBudget,
                                      hideSelected: posterT > 0.02,
                                      items: _railItems(items, api),
                                      selection: _selected.clamp(
                                        0,
                                        items.isEmpty ? 0 : items.length - 1,
                                      ),
                                      size: size,
                                      motion: motion,
                                      onSelect: (i) {
                                        _collapse();
                                        setState(() => _selected = i);
                                      },
                                      onActivate: (i) => _activate(items, i),
                                      emptyLabel: switch ((
                                        async.isLoading,
                                        _mode,
                                      )) {
                                        (true, _) => 'Loading…',
                                        (false, BrowseMode.collections) =>
                                          'No collections in this library',
                                        (false, BrowseMode.singles) =>
                                          'No movies in this library',
                                      },
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),

                  // Cast, rising from beneath where the rail was.
                  if (castT > 0 && detailed != null)
                    Positioned(
                      left: gutter,
                      right: gutter,
                      bottom: bottomPad,
                      child: Opacity(
                        opacity: castT,
                        child: Transform.translate(
                          offset: Offset(0, 40 * (1 - castT)),
                          child: MoviesCastRow(
                            people: detailed.people.take(12).toList(),
                            height: media.size.height * 0.20,
                            imageUrlFor: (id) => api.imageUrl(id),
                          ),
                        ),
                      ),
                    ),

                  // The flying poster, above everything it travels across.
                  if (posterT > 0 && selected != null)
                    MoviesHeroPoster(
                      imageUrl: api.imageUrl(
                        selected.id,
                        tag: selected.imageTags?['Primary'],
                      ),
                      rect: posterRect,
                      elevation: posterT,
                    ),
                ],
              );
            },
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
    required this.showPlay,
    required this.actionsProgress,
    required this.onOpen,
    required this.onCollapse,
  });

  final LibraryItem? item;
  final LibraryItem? collection;
  final bool loading;
  final String? error;
  final VoidCallback? onPlay;
  final VoidCallback? onBack;

  /// The Play control moves into the action bar once the stage expands, so it
  /// is not drawn in two places at once during the move.
  final bool showPlay;

  /// 0..1 across the actions interval.
  final double actionsProgress;
  final VoidCallback? onOpen;
  final VoidCallback onCollapse;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (collection != null) ...[
          Row(
            children: [
              AnalogIconButton(
                icon: Icons.arrow_back,
                tooltip: 'Back to collections',
                onPressed: onBack,
              ),
              const SizedBox(width: AnalogSpace.smPx),
              Text(
                collection!.name.toUpperCase(),
                style: const TextStyle(
                  fontFamily: AnalogType.monoFamily,
                  fontSize: 11,
                  letterSpacing: 1.4,
                  color: AnalogColor.inkDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: AnalogSpace.mdPx),
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
          const SizedBox(height: AnalogSpace.smPx),
          Row(
            children: [
              Text(
                _metaLine(current),
                style: const TextStyle(
                  fontFamily: AnalogType.monoFamily,
                  fontSize: 12,
                  letterSpacing: 0.6,
                  color: AnalogColor.inkDim,
                ),
              ),
              // Ratings are a different kind of fact from the meta line — an
              // opinion rather than a property — so they read as a mark rather
              // than as another item in the run of text.
              if (current.communityRating != null) ...[
                const SizedBox(width: AnalogSpace.mdPx),
                const Icon(Icons.star, size: 13, color: AnalogColor.inkDim),
                const SizedBox(width: 4),
                Text(
                  current.communityRating!.toStringAsFixed(1),
                  style: const TextStyle(
                    fontFamily: AnalogType.monoFamily,
                    fontSize: 12,
                    color: AnalogColor.ink,
                  ),
                ),
              ],
            ],
          ),
          if (current.genres.isNotEmpty) ...[
            const SizedBox(height: AnalogSpace.smPx),
            Wrap(
              spacing: AnalogSpace.xsPx,
              runSpacing: AnalogSpace.xsPx,
              children: [
                for (final genre in current.genres.take(4))
                  AnalogBadge.outline(
                    child: Text(
                      genre,
                      style: const TextStyle(
                        fontFamily: AnalogType.sansFamily,
                        fontSize: 11,
                        color: AnalogColor.inkDim,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if ((current.taglines.isNotEmpty)) ...[
            const SizedBox(height: AnalogSpace.mdPx),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
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
            ),
          ],
          if ((current.overview ?? '').isNotEmpty) ...[
            const SizedBox(height: AnalogSpace.mdPx),
            ConstrainedBox(
              // Overview is prose: hold it near a readable measure rather than
              // letting it run the full width of a desktop stage.
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                current.overview!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AnalogType.sansFamily,
                  fontSize: 14,
                  height: 1.5,
                  color: AnalogColor.inkDim,
                ),
              ),
            ),
          ],
          const SizedBox(height: AnalogSpace.lgPx),
          if (onPlay != null && showPlay)
            AnalogButton(
              label: current.type == collectionType ? 'Open collection' : 'Play',
              icon: current.type == collectionType
                  ? Icons.folder_open
                  : Icons.play_arrow,
              tone: AnalogButtonTone.primary,
              onPressed: onPlay,
            ),
          if (actionsProgress > 0)
            MoviesActionBar(
              progress: actionsProgress,
              downloadBusy: false,
              onPlay: onOpen,
              onDownload: onOpen,
              onBack: onCollapse,
            ),
        ],
      ],
    );
  }

  /// Year, certificate and runtime — the facts that are the same shape for
  /// every title, so the line does not reflow as you step along the rail.
  static String _metaLine(LibraryItem item) {
    final parts = <String>[
      if (item.productionYear != null) '${item.productionYear}',
      if ((item.officialRating ?? '').isNotEmpty) item.officialRating!,
      if (item.runTimeTicks != null && item.runTimeTicks! > 0)
        _runtime(item.runTimeTicks!),
    ];
    return parts.join('  ·  ');
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
