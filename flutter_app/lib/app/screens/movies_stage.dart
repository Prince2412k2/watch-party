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

import 'package:flutter/material.dart';
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
        context.push('/detail/$itemId');
      case NoActivation():
        break;
    }
  }

  void _back() {
    if (_collection != null) setState(() => _collection = null);
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

    final media = MediaQuery.of(context);
    final size = stageLayout(
      media.size.width,
      media.size.height,
      false,
    ).size;
    final motion = motionProfile(media.disableAnimations);

    return AnalogStage(
      backdropUrl: selected == null
          ? null
          : api.imageUrl(selected.id, type: ImageType.backdrop),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: size == StageSize.phone
              ? AnalogSpace.stageGutterPhonePx
              : AnalogSpace.stageGutterPx,
          vertical: AnalogSpace.xlPx,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Details on top — the main event now that there is no
                  // separate movie detail page to open.
                  Expanded(
                    child: _Details(
                      item: selected,
                      collection: _collection,
                      loading: async.isLoading,
                      error: async.hasError ? 'Could not load this library' : null,
                      onPlay: selected == null
                          ? null
                          : () => _activate(items, _selected),
                      onBack: _collection == null ? null : _back,
                    ),
                  ),
                  const SizedBox(width: AnalogSpace.xlPx),
                  // The mode strip sits on the side, the way seasons do on the
                  // show screen. Hidden inside a franchise, where the only
                  // meaningful move is back out.
                  if (_collection == null)
                    _ModeStrip(mode: _mode, onChanged: _setMode),
                ],
              ),
            ),
            const SizedBox(height: AnalogSpace.lgPx),
            AnalogRail(
              items: [
                for (final item in items)
                  AnalogRailItem(
                    id: item.id,
                    label: item.name,
                    subtitle: item.productionYear?.toString(),
                    imageUrl: api.imageUrl(
                      item.id,
                      tag: item.imageTags?['Primary'],
                    ),
                    progress: _progressOf(item),
                  ),
              ],
              selection: _selected.clamp(0, items.isEmpty ? 0 : items.length - 1),
              size: size,
              motion: motion,
              autofocus: true,
              onSelect: (i) => setState(() => _selected = i),
              onActivate: (i) => _activate(items, i),
              onCrossAxis: _collection == null ? _stepMode : null,
              onEscape: _collection == null ? null : _back,
              emptyLabel: switch ((async.isLoading, _mode)) {
                (true, _) => 'Loading…',
                (false, BrowseMode.collections) => 'No collections in this library',
                (false, BrowseMode.singles) => 'No movies in this library',
              },
            ),
          ],
        ),
      ),
    );
  }

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
          Text(
            _metaLine(current),
            style: const TextStyle(
              fontFamily: AnalogType.monoFamily,
              fontSize: 12,
              letterSpacing: 0.6,
              color: AnalogColor.inkDim,
            ),
          ),
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
          if (onPlay != null)
            AnalogButton(
              label: current.type == collectionType ? 'Open collection' : 'Play',
              icon: current.type == collectionType
                  ? Icons.folder_open
                  : Icons.play_arrow,
              tone: AnalogButtonTone.primary,
              onPressed: onPlay,
            ),
        ],
      ],
    );
  }

  static String _metaLine(LibraryItem item) {
    final parts = <String>[
      if (item.productionYear != null) '${item.productionYear}',
      if ((item.officialRating ?? '').isNotEmpty) item.officialRating!,
      if (item.runTimeTicks != null && item.runTimeTicks! > 0)
        _runtime(item.runTimeTicks!),
      if (item.genres.isNotEmpty) item.genres.take(2).join(', '),
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
