import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import 'artwork_wall.dart';
import 'pasted_artwork.dart';
import 'textured_artwork.dart';

/// Same-origin artwork, painted as if it were pasted to the wall behind it.
///
/// This exists because a fragment shader takes *samplers*, not widgets, so the
/// artwork has to be a decoded [ui.Image] before it can be pasted. Everywhere
/// else in the app artwork is an `AuthedNetworkImage`, which renders bytes and
/// never hands them out — so the bytes are fetched from the same cache here and
/// decoded once.
///
/// Three more images go in with it: the wall's relief, its colour, and a sheet
/// of paper. All are bundled and cached process-wide, so the cost is one decode
/// each for the whole app rather than one per tile.
class ShadedArtwork extends ConsumerStatefulWidget {
  const ShadedArtwork({
    super.key,
    required this.url,
    required this.settings,
    this.wallSeed,
    this.paperSeed,
    this.portrait = true,
    this.errorBuilder,
  });

  final String url;

  /// Which uniforms this surface paints with — [ArtworkPaste.poster] or
  /// [ArtworkPaste.backdrop]. They differ only in how much paper they take.
  final PasteShaderSettings settings;

  /// The room's wall. Every surface in a room must agree on it, or the courses
  /// would stop at each poster's edge.
  final String? wallSeed;

  /// Which of the ten sheets this artwork is printed on. An item id, so a title
  /// keeps its paper — and so a rail shows all ten rather than one repeated.
  final String? paperSeed;

  final bool portrait;
  final Widget Function(BuildContext context)? errorBuilder;

  @override
  ConsumerState<ShadedArtwork> createState() => _ShadedArtworkState();
}

class _ShadedArtworkState extends ConsumerState<ShadedArtwork> {
  StreamSubscription<Uint8List>? _bytes;
  ui.Image? _art;
  ui.Image? _wall;
  ui.Image? _depth;
  ui.Image? _paper;
  ui.FragmentProgram? _program;
  Object? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadFixtures();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadArt());
  }

  @override
  void didUpdateWidget(ShadedArtwork old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _loadArt();
    if (old.wallSeed != widget.wallSeed ||
        old.paperSeed != widget.paperSeed ||
        old.portrait != widget.portrait) {
      _loadFixtures();
    }
  }

  @override
  void dispose() {
    _bytes?.cancel();
    super.dispose();
  }

  Future<void> _loadFixtures() async {
    final wallIndex = ArtworkWall.indexFor(widget.wallSeed);
    final sheet = ArtworkTexture.sheetFor(
      widget.paperSeed,
      portrait: widget.portrait,
    );
    final program = await PasteShader.load();
    // Raw, not eased: the shader does its own arithmetic on the depth, and
    // pre-flattening it would leave nothing for the gradient to find.
    final depth = await WallImages.load(ArtworkWall.depth(wallIndex));
    final wall = await WallImages.load(ArtworkWall.tint(wallIndex));
    final paper = await WallImages.load(sheet);
    if (!mounted) return;
    setState(() {
      _program = program;
      _depth = depth;
      _wall = wall;
      _paper = paper;
    });
  }

  Future<void> _loadArt() async {
    final generation = ++_generation;
    _bytes?.cancel();
    final cache = ref.read(artworkCacheProvider);
    if (cache == null) return;

    Future<void> decode(Uint8List bytes) async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || generation != _generation) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _art = frame.image;
        _error = null;
      });
    }

    final peeked = cache.peek(widget.url);
    if (peeked != null) await decode(peeked);
    _bytes = cache
        .load(widget.url)
        .listen(
          (bytes) {
            if (mounted && generation == _generation) decode(bytes);
          },
          onError: (Object error, StackTrace _) {
            if (mounted && generation == _generation) {
              setState(() => _error = error);
            }
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context);
    }
    final art = _art;
    final wall = _wall;
    final depth = _depth;
    final paper = _paper;
    final program = _program;
    if (art == null) return const SizedBox.expand();
    if (wall == null || depth == null || paper == null || program == null) {
      // Plain artwork until the wall and the shader arrive. A hole where a
      // poster should be, on every cold start, is worse than a poster that
      // gains its texture a frame late.
      return RawImage(image: art, fit: BoxFit.cover);
    }
    return _Anchored(
      builder: (context, origin) => CustomPaint(
        painter: PastedPosterPainter(
          program: program,
          poster: art,
          wall: wall,
          depth: depth,
          paper: paper,
          origin: origin,
          window: MediaQuery.sizeOf(context),
          settings: widget.settings,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Reports where it sits in the window, so the wall can be sampled there.
///
/// Nothing above this knows the offset: a poster's place on screen depends on
/// how far its rail has scrolled. Read after layout and fed back as state, so
/// the first frame paints at the previous offset and every frame after is
/// right.
class _Anchored extends StatefulWidget {
  const _Anchored({required this.builder});

  final Widget Function(BuildContext context, Offset origin) builder;

  @override
  State<_Anchored> createState() => _AnchoredState();
}

class _AnchoredState extends State<_Anchored> {
  Offset _origin = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(_Anchored old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _measure() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final origin = box.localToGlobal(Offset.zero);
    if (origin != _origin) setState(() => _origin = origin);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _origin);
}
