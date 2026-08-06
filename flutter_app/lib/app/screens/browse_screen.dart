import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../analog/analog.dart';
import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import '../../ui/analog_tokens.dart';
import '../../ui/ui.dart';

/// Route-scoped Movies or Shows library, rebuilt on the analog kit (#66).
///
/// The stage is the surface: the focused title's backdrop fills it and
/// cross-fades as focus moves, with horizontal [AnalogShelf]s over the top —
/// a main shelf for the current type, then a shelf per genre that forms a
/// meaningful subset (more than one title, fewer than the whole set). Never a
/// grid, and still no search field.
///
/// What changed against the old implementation, beyond the paint:
///
/// * **Selection is no longer private.** It lives here and is mirrored into
///   [analogFocusProvider], so leaving for `/detail/:id` and coming back lands
///   on the item you left from — via the shared [restoreFocus] core, including
///   when that item has since disappeared from the shelf.
/// * **The wheel goes through [steppedScroll]**, so a trackpad flick moves one
///   item instead of coasting, and it moves the same number of items it would
///   in the React client on the same hardware.
/// * **Arrow up/down work**, because the shelves sit in a
///   [FocusTraversalGroup] and [AnalogShelf] deliberately leaves the vertical
///   axis to directional traversal. That is also D-pad/remote support, which
///   nothing in this tree had.
/// * **Artwork is square and 2:3.** The old screen drew 3/5 with a 12px radius.
class BrowseScreen extends ConsumerStatefulWidget {
  const BrowseScreen({super.key, required this.type});

  final BrowseTypeFilter type;

  @override
  ConsumerState<BrowseScreen> createState() => _BrowseScreenState();
}

/// One horizontal collection on the stage.
class _Shelf {
  const _Shelf({required this.id, required this.title, required this.items});

  final String id;
  final String title;
  final List<LibraryItem> items;

  ShelfSnapshot get snapshot =>
      ShelfSnapshot(shelfId: id, itemIds: [for (final it in items) it.id]);
}

class _BrowseScreenState extends ConsumerState<BrowseScreen> {
  /// Focused item index per shelf id.
  final Map<String, int> _itemIndex = {};
  final Map<String, FocusNode> _shelfNodes = {};

  String? _focusedShelfId;
  bool _restored = false;

  String get _surfaceId => 'browse:${widget.type.name}';

  String get _title => widget.type == BrowseTypeFilter.movie ? 'Movies' : 'Shows';

  @override
  void dispose() {
    for (final node in _shelfNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _nodeFor(String shelfId) => _shelfNodes.putIfAbsent(
    shelfId,
    () => FocusNode(debugLabel: 'analog-shelf:$shelfId'),
  );

  LibraryItem? _focusedItem(List<_Shelf> shelves) {
    for (final shelf in shelves) {
      if (shelf.id != _focusedShelfId) continue;
      final index = _itemIndex[shelf.id] ?? 0;
      if (index < 0 || index >= shelf.items.length) return null;
      return shelf.items[index];
    }
    return null;
  }

  /// Place focus for the first frame of real data.
  ///
  /// Run synchronously inside `build` rather than from a post-frame callback,
  /// because `autofocus` is only honoured on a [Focus] widget's first build —
  /// deferring this by a frame would mean the restored shelf never actually
  /// takes keyboard focus.
  void _restoreOnce(List<_Shelf> shelves) {
    if (_restored || shelves.isEmpty) return;
    _restored = true;

    final result = ref
        .read(analogFocusProvider.notifier)
        .restore(_surfaceId, [for (final s in shelves) s.snapshot]);
    final position = result.position;
    if (position == null) return;

    _focusedShelfId = position.shelfId;
    for (final shelf in shelves) {
      if (shelf.id != position.shelfId) continue;
      final index = shelf.items.indexWhere((it) => it.id == position.itemId);
      _itemIndex[shelf.id] = index < 0 ? 0 : index;
    }
    _pushAmbient(position.itemId);
  }

  /// Ambient artwork is a provider write, so it can never happen during build.
  void _pushAmbient(String itemId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(ambientArtworkIdProvider.notifier).state = itemId;
      }
    });
  }

  void _focusItem(_Shelf shelf, int index) {
    if (index < 0 || index >= shelf.items.length) return;
    setState(() {
      _focusedShelfId = shelf.id;
      _itemIndex[shelf.id] = index;
    });
    final item = shelf.items[index];
    ref
        .read(analogFocusProvider.notifier)
        .remember(
          _surfaceId,
          FocusPosition(shelfId: shelf.id, itemId: item.id),
          index,
        );
    ref.read(ambientArtworkIdProvider.notifier).state = item.id;
  }

  /// Directional traversal moved focus onto another shelf. Deferred a frame
  /// because `Focus.onFocusChange` can fire mid-build, and both the state and
  /// the ambient provider writes below are illegal there.
  void _onShelfFocus(_Shelf shelf, bool hasFocus) {
    if (!hasFocus || _focusedShelfId == shelf.id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || shelf.items.isEmpty) return;
      _focusItem(
        shelf,
        (_itemIndex[shelf.id] ?? 0).clamp(0, shelf.items.length - 1),
      );
    });
  }

  /// A step off the end of a shelf continues into the next collection, which
  /// is what makes a wheel-only mouse able to reach every shelf.
  void _onEdge(List<_Shelf> shelves, int shelfIndex, int direction) {
    final next = shelfIndex + direction;
    if (next < 0 || next >= shelves.length) return;
    _nodeFor(shelves[next].id).requestFocus();
  }

  void _activate(_Shelf shelf, int index) {
    if (index < 0 || index >= shelf.items.length) return;
    _focusItem(shelf, index);
    context.go('/detail/${shelf.items[index].id}');
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(browseByTypeProvider(widget.type));
    final api = ref.watch(apiClientProvider);

    return items.when(
      loading: () => const AnalogStage(child: _BrowseSkeleton()),
      error: (e, _) => AnalogStage(
        child: ErrorState(
          title: 'Failed to load library',
          message: '$e',
          onRetry: () => ref.invalidate(browseByTypeProvider(widget.type)),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const AnalogStage(
            child: EmptyState(
              title: 'No titles here yet',
              message: 'Add something from Discover.',
              icon: Icons.movie_filter_outlined,
            ),
          );
        }

        final shelves = _buildShelves(list);
        _restoreOnce(shelves);
        final focused = _focusedItem(shelves);

        return AnalogStage(
          backdropUrl: focused == null
              ? null
              : api.imageUrl(focused.id, type: ImageType.backdrop),
          focused: focused != null,
          child: LayoutBuilder(
            builder: (context, constraints) =>
                _stage(context, api, shelves, constraints),
          ),
        );
      },
    );
  }

  /// Main shelf for the current type, then genre-subset shelves — a genre that
  /// more than one, but not all, titles share (web `GridView.genreRows`).
  List<_Shelf> _buildShelves(List<LibraryItem> list) {
    final shelves = <_Shelf>[
      _Shelf(id: 'all', title: _title, items: list),
    ];
    final genres = <String>{for (final it in list) ...it.genres};
    for (final genre in genres) {
      final subset = list.where((it) => it.genres.contains(genre)).toList();
      if (subset.length > 1 && subset.length < list.length) {
        shelves.add(_Shelf(id: 'genre:$genre', title: genre, items: subset));
      }
    }
    return shelves;
  }

  Widget _stage(
    BuildContext context,
    ApiClient api,
    List<_Shelf> shelves,
    BoxConstraints constraints,
  ) {
    // flutter_app ships linux/macos/windows only — there is no phone target
    // here, so "narrow" means a narrow WINDOW, not a handset. It buys a
    // tighter gutter and a smaller poster, not a different layout.
    final narrow = constraints.maxWidth <= AnalogBreakpoint.phoneMaxPx;
    final gutter = narrow
        ? AnalogSpace.stageGutterPhonePx
        : AnalogSpace.stageGutterPx;
    final bottomInset = AnalogSpace.stageGutterPx * 2;

    final posterWidth = shelves.length == 1
        ? _fillWidth(constraints.maxHeight - AnalogSpace.xlPx - bottomInset)
        : (narrow ? 150.0 : 200.0);
    final slotHeight =
        AnalogPosterTile.artHeightFor(posterWidth) +
        AnalogPosterTile.captionHeight();

    final built = <Widget>[
      for (var i = 0; i < shelves.length; i++)
        _shelfWidget(api, shelves, i, posterWidth, slotHeight),
    ];

    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          gutter,
          AnalogSpace.xlPx,
          0,
          bottomInset,
        ),
        child: shelves.length == 1
            ? Align(alignment: Alignment.centerLeft, child: built.first)
            : ListView.separated(
                itemCount: built.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AnalogSpace.xxlPx),
                itemBuilder: (_, index) => built[index],
              ),
      ),
    );
  }

  /// Largest poster width whose shelf still fits in [available] vertical
  /// pixels once the heading, caption and focus overflow are reserved.
  ///
  /// The focus overflow is proportional to the artwork height (the scale) plus
  /// a fixed lift and shadow offset, so solving for the artwork height means
  /// dividing through by the scale rather than subtracting a guess. [_slackPx]
  /// covers a non-default text scale, which would otherwise push the pinned
  /// line heights past their reservation.
  static const double _slackPx = AnalogSpace.smPx;

  static double _fillWidth(double available) {
    final fixed =
        AnalogShelf.headingHeight +
        AnalogPosterTile.captionHeight() +
        2 * AnalogSelection.focusLiftPx +
        AnalogElevation.focusOffsetYPx +
        _slackPx;
    final artHeight = (available - fixed) / AnalogSelection.focusScale;
    final width = artHeight * AnalogPoster.aspectW / AnalogPoster.aspectH;
    return width.clamp(140.0, 260.0);
  }

  Widget _shelfWidget(
    ApiClient api,
    List<_Shelf> shelves,
    int shelfIndex,
    double posterWidth,
    double slotHeight,
  ) {
    final shelf = shelves[shelfIndex];
    final focusedIndex = (_itemIndex[shelf.id] ?? 0).clamp(
      0,
      shelf.items.length - 1,
    );
    return AnalogShelf(
      key: ValueKey('analog-shelf-${shelf.id}'),
      focusNode: _nodeFor(shelf.id),
      title: shelf.title,
      itemCount: shelf.items.length,
      itemWidth: posterWidth,
      itemHeight: slotHeight,
      focusedIndex: focusedIndex,
      autofocus: shelf.id == _focusedShelfId,
      onFocusChanged: (index) => _focusItem(shelf, index),
      onActivate: (index) => _activate(shelf, index),
      onEdge: (direction) => _onEdge(shelves, shelfIndex, direction),
      onShelfFocusChanged: (has) => _onShelfFocus(shelf, has),
      semanticLabelBuilder: (index) => shelf.items[index].name,
      itemBuilder: (context, index, focused) {
        final item = shelf.items[index];
        return AnalogPosterTile(
          title: item.name,
          imageUrl: api.imageUrl(item.id, tag: item.imageTags?['Primary']),
          width: posterWidth,
          focused: focused && shelf.id == _focusedShelfId,
          // The Hero has to stay unique across shelves: a genre shelf shows
          // the same title as the main shelf, and two live Heroes with one tag
          // is a hard error on the way to /detail/:id.
          heroTag: shelf.id == 'all' ? 'poster-${item.id}' : null,
        );
      },
    );
  }
}

class _BrowseSkeleton extends StatelessWidget {
  const _BrowseSkeleton();

  static const double _width = 200;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AnalogSpace.stageGutterPx,
        AnalogSpace.xlPx,
        0,
        AnalogSpace.stageGutterPx,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 180, height: 24, color: AnalogColor.stageSurface2),
          const SizedBox(height: AnalogSpace.lgPx),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height:
                    AnalogPosterTile.artHeightFor(_width) +
                    AnalogSpace.xxlPx,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 8,
                  separatorBuilder: (_, _) =>
                      const SizedBox(width: AnalogPoster.gapPx),
                  itemBuilder: (_, _) =>
                      const AnalogPosterSkeleton(width: _width),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
