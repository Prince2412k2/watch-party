import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

/// The wall the whole stage is hung on, and the paper everything is printed on.
///
/// A wall is two files. `depth-NN.jpg` is a normalised relief map — brick,
/// mortar, blown plaster — and is what actually gets seen: it is soft-lit over
/// whatever is beneath, so it reads as light falling across a surface rather
/// than as a picture of a wall. `tint-NN.jpg` is the colour and dirt, laid on
/// at a low constant opacity.
///
/// The relief maps were normalised when they were baked. The sources span only
/// about 0.40–0.74, so stored as-is an 8-bit file throws away most of the
/// relief and JPEG bands what survives; [kReliefStrength] compensates by
/// blending the stretched map back down.
abstract final class ArtworkWall {
  static const int count = 10;

  static String depth(int index) =>
      'assets/textures/wall/depth-${_two(index)}.jpg';

  static String tint(int index) =>
      'assets/textures/wall/tint-${_two(index)}.jpg';

  /// The colour layer's opacity. The sources carried a flat ~8% alpha which was
  /// dropped at bake time — this puts it back.
  static const double kTintOpacity = 0.0;

  /// How hard the relief is pressed into the bare wall.
  ///
  /// Zero: the wall is no longer drawn as a surface of its own. It exists only
  /// inside `shaders/pasted_poster.frag`, as the thing whose relief lights the
  /// artwork lying on it — so there is nothing left for a soft-light pass over
  /// bare ground to do. Raise it and the bare stage grows visible brick again,
  /// which is only ever seen when no title is selected.
  static const double kReliefStrength = 0.0;

  /// The relief through the backdrop sheet. Deeper than a poster's, because the
  /// backdrop is the largest thing on the stage and reads as scenery — it is
  /// what has to sell the room — and because the scrim and vignette over it eat
  /// a good deal of the relief before it reaches the eye.
  static const double kBackdropPasteStrength = 0.0;

  /// The relief through a poster. Kept well back: a poster is a small sheet of
  /// paper over the brick, not the brick itself, so it takes the shape of what
  /// it is stuck to without taking its full texture — and unlike the backdrop
  /// it is artwork someone is trying to read at rail size.
  static const double kPasteStrength = 0.0;

  /// Relief tuning, baked into the map alongside strength and taken about
  /// mid-grey — which is soft-light's no-op, so "no relief" and "no adjustment"
  /// are the same point and the three cannot fight each other.
  ///
  /// The contrast is well above 1 because the sources span only ~0.40-0.74 even
  /// after the bake normalises them; without it the brick reads as a smudge
  /// rather than as courses.
  static const double kReliefBrightness = -0.500;
  static const double kReliefContrast = 0.200;

  static String _two(int i) => (i % count).abs().toString().padLeft(2, '0');

  /// Which wall a given room gets. Stable for a seed, so a library keeps its
  /// wall between visits instead of redecorating on every navigation.
  static int indexFor(String? seed) {
    if (seed == null || seed.isEmpty) return 0;
    var hash = 0;
    for (var i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7fffffff;
    }
    return hash % count;
  }
}

/// Decoded wall images, shared by every surface using them.
///
/// One wall covers the whole window and is asked for by the stage and by every
/// poster on it at once, so this is cached by asset key. The futures are held
/// rather than the images, so ten simultaneous first-frame requests still
/// decode once.
class WallImages {
  WallImages._();

  static final Map<String, Future<ui.Image>> _cache = {};

  /// [load], with the relief eased back toward flat grey — soft-light's no-op —
  /// so a poster can take the wall's shape without taking its full texture.
  ///
  /// Baked into an image rather than applied at paint time because the drawing
  /// is a [ShaderMaskLayer], which takes a shader and no paint, so there is
  /// nowhere to hang an opacity or a colour filter. There are only ever two
  /// strengths in play, so this costs one extra decode each and then nothing.
  static Future<ui.Image> loadEased(
    String key,
    double strength, {
    double brightness = 0,
    double contrast = 1,
  }) => _cache.putIfAbsent('$key@$strength/$brightness/$contrast', () async {
    final full = await load(key);
    if (strength >= 1 && brightness == 0 && contrast == 1) return full;
    // Contrast and brightness are taken about mid-grey, then the whole thing
    // is eased back toward mid-grey by strength — because mid-grey is
    // soft-light's no-op, so "no relief" and "no adjustment" are the same
    // point and the three controls cannot fight each other.
    //
    //   out = 0.5 + (((v - 0.5) * contrast) + brightness) * strength
    final scale = contrast * strength;
    final offset = (0.5 - 0.5 * scale + brightness * strength) * 255;
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImage(
      full,
      Offset.zero,
      Paint()
        ..colorFilter = ColorFilter.matrix(<double>[
          scale, 0, 0, 0, offset, //
          0, scale, 0, 0, offset, //
          0, 0, scale, 0, offset, //
          0, 0, 0, 1, 0, //
        ]),
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(full.width, full.height);
    picture.dispose();
    return out;
  });

  static Future<ui.Image> load(String key) =>
      _cache.putIfAbsent(key, () async {
        final data = await rootBundle.load(key);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        return frame.image;
      });

  /// Drops the decoded walls.
  ///
  /// Tests need this and need it badly: the cache holds *Futures*, and a Future
  /// created inside one `testWidgets` fake-async zone never completes inside
  /// another. A second test asking for a wall a first test already loaded would
  /// wait on it forever and silently render no wall at all — passing, while
  /// proving nothing.
  @visibleForTesting
  static void debugClear() => _cache.clear();
}

/// Presses a wall's relief into everything below it, **anchored to the window**
/// rather than to the widget.
///
/// This is the whole trick, and the reason it is a render object rather than a
/// `ShaderMask`. If each poster sampled the relief from its own top-left, every
/// poster would show the same brick starting in the same corner, twenty little
/// walls instead of one wall behind twenty posters. Sampling from the window
/// origin means the courses run straight through the artwork and out the other
/// side, which is what makes a poster look stuck to the wall instead of
/// floating in front of a photograph of one.
///
/// The offset is read at paint time via [RenderBox.localToGlobal], so it stays
/// correct while a rail scrolls and while a focused tile scales — a value
/// captured at layout would lag by a frame and the bricks would swim.
class WallRelief extends SingleChildRenderObjectWidget {
  const WallRelief({
    super.key,
    required this.depth,
    required this.strength,
    required super.child,
  });

  /// The decoded relief map, or null while it is still being decoded — in which
  /// case the child is painted plainly rather than not at all.
  final ui.Image? depth;

  /// Kept only so a caller can switch the effect off wholesale; the easing
  /// itself is baked into [depth] by [WallImages.loadEased], because a
  /// ShaderMaskLayer has no paint to hang an opacity on.
  final double strength;

  @override
  RenderProxyBox createRenderObject(BuildContext context) => _RenderWallRelief(
    depth,
    strength,
    MediaQuery.sizeOf(context),
  );

  @override
  void updateRenderObject(BuildContext context, RenderProxyBox renderObject) {
    (renderObject as _RenderWallRelief)
      ..depth = depth
      ..strength = strength
      ..window = MediaQuery.sizeOf(context);
  }
}

class _RenderWallRelief extends RenderProxyBox {
  _RenderWallRelief(this._depth, this._strength, this._window);

  ui.Image? _depth;
  set depth(ui.Image? value) {
    if (value == _depth) return;
    _depth = value;
    markNeedsPaint();
  }

  double _strength;
  set strength(double value) {
    if (value == _strength) return;
    _strength = value;
    markNeedsPaint();
  }

  Size _window;
  set window(Size value) {
    if (value == _window) return;
    _window = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final depth = _depth;
    if (child == null) return;
    if (depth == null || _strength <= 0 || size.isEmpty || _window.isEmpty) {
      super.paint(context, offset);
      return;
    }

    // Cover the window with one copy of the wall, aspect preserved.
    final scale = _coverScale(depth, _window);

    // A ShaderMaskLayer's shader is sampled from the mask rect's top-left, so
    // the shader has to be shifted back by wherever that corner sits on screen.
    // Everything then samples the same wall from the same origin.
    final origin = localToGlobal(Offset.zero);
    final matrix = Matrix4.identity()
      ..translateByDouble(-origin.dx, -origin.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);

    context.pushLayer(
      ShaderMaskLayer()
        ..shader = ui.ImageShader(
          depth,
          TileMode.clamp,
          TileMode.clamp,
          matrix.storage,
        )
        ..maskRect = offset & size
        ..blendMode = BlendMode.softLight,
      super.paint,
      offset,
    );
  }

  static double _coverScale(ui.Image image, Size window) {
    final byWidth = window.width / image.width;
    final byHeight = window.height / image.height;
    return byWidth > byHeight ? byWidth : byHeight;
  }
}

/// Loads a wall and hands its relief to [builder].
///
/// Split out because the stage and every poster want the same two images and
/// none of them should each be a `FutureBuilder` over `rootBundle`.
class WallLayer extends StatefulWidget {
  const WallLayer({
    super.key,
    required this.index,
    required this.builder,
    required this.strength,
    this.withTint = false,
    this.brightness = 0,
    this.contrast = 1,
  });

  final int index;

  /// How hard this surface takes the relief. Eased into the map at decode time.
  final double strength;

  /// Relief tuning, also baked into the map. Both are taken about mid-grey.
  final double brightness;
  final double contrast;

  /// Also decode the colour layer. Only the stage wants it: on a poster the
  /// dirt would sit *over* the artwork, which is not where dirt on a wall goes.
  final bool withTint;

  final Widget Function(BuildContext context, ui.Image? depth, ui.Image? tint)
  builder;

  @override
  State<WallLayer> createState() => _WallLayerState();
}

class _WallLayerState extends State<WallLayer> {
  ui.Image? _depth;
  ui.Image? _tint;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(WallLayer old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index ||
        old.withTint != widget.withTint ||
        old.strength != widget.strength ||
        old.brightness != widget.brightness ||
        old.contrast != widget.contrast) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final index = widget.index;
    final depth = await WallImages.loadEased(
      ArtworkWall.depth(index),
      widget.strength,
      brightness: widget.brightness,
      contrast: widget.contrast,
    );
    final tint = widget.withTint
        ? await WallImages.load(ArtworkWall.tint(index))
        : null;
    // The index can change while these are in flight; a stale wall arriving
    // after a newer one would quietly swap the room back.
    if (!mounted || index != widget.index) return;
    setState(() {
      _depth = depth;
      _tint = tint;
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _depth, _tint);
}
