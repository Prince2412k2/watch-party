import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

/// The stock sheets, by the surface each was cut for.
///
/// Two rather than one because the sheets are not tiles: each is a framed piece
/// of paper with its own worn border, sized to the shape it prints on. Feeding
/// the square backdrop sheet to a 2:3 poster would crop that border off two
/// sides and leave the tear looking sawn rather than torn.
abstract final class ArtworkTexture {
  static const String backdrop = 'assets/textures/backdrop.png';
  static const String poster = 'assets/textures/poster.png';
}

/// Artwork printed on aged stock: fibre in the image, a warm sheet behind it,
/// and torn edges that genuinely remove pixels rather than paint over them.
///
/// ## One asset, two jobs
///
/// `assets/textures/*.png` is greyscale-plus-alpha. The **RGB** is the paper
/// fibre, soft-lit into both the sheet and the artwork. The **alpha** is the
/// wear: opaque where the stock is intact, transparent where it has worn
/// through. Both were baked from the same luminance, so the grain and the tear
/// always agree about where the sheet is thin — which is what stops the tear
/// reading as a shape cut out of an otherwise pristine picture.
///
/// ## Why the ink wears away sooner than the sheet
///
/// If one mask cut both, the paper would be removed everywhere the ink is and
/// [paper] would never show — the treatment would be an expensive way to draw
/// a grey rectangle. So the baked alpha is the **ink** wear, and [_stockOf]
/// widens that same channel toward opaque to get the larger **sheet** shape.
/// Between the two you see bare paper, which is the entire point.
///
/// ## Why ShaderMask and not a hand-rolled saveLayer
///
/// The obvious implementation — a `RenderProxyBox` that calls
/// `canvas.saveLayer`, paints its child, then `restore`s — is broken, and
/// quietly. A descendant that pushes its own compositing layer (`ColorFiltered`
/// does) makes `PaintingContext` stop the current recording and continue on a
/// *different* canvas, so the `restore` lands on a canvas that was never saved,
/// the pairs go unbalanced, and the whole subtree is dropped. It renders as the
/// bare texture with the artwork and paper colour silently missing.
/// [ShaderMask] pushes a real `ShaderMaskLayer` and composes correctly.
class TexturedArtwork extends StatefulWidget {
  const TexturedArtwork({
    super.key,
    required this.texture,
    required this.child,
    this.paper = kWarmPaper,
    this.enabled = true,
    this.shadow,
  });

  /// The baked greyscale+alpha sheet, e.g. `assets/textures/poster.png`.
  final String texture;

  /// The artwork to print.
  final Widget child;

  /// Stock colour. [paperFor] mixes this from [kWarmPaper] and the artwork.
  final Color paper;

  /// Off returns [child] untouched, so a caller can A/B the treatment without
  /// restructuring its tree — and so existing layout tests keep their shape.
  final bool enabled;

  /// Cast shadow, thrown from the **torn silhouette** rather than from the
  /// widget's box. A rectangular shadow under ragged paper is the tell that
  /// gives the whole effect away: the eye reads the shadow's corners as the
  /// object's corners, and the tear stops being a shape and becomes a pattern
  /// printed on a square. Drawn from the sheet's own alpha, so it costs one
  /// masked fill rather than a second pass over the artwork.
  final BoxShadow? shadow;

  /// The base stock: warm, low-chroma, lighter than the stage so a torn edge
  /// reads as paper catching light rather than as a hole punched in the screen.
  static const Color kWarmPaper = Color(0xFFD8C3A0);

  /// How far the artwork's own colour may pull the stock. Deliberately small:
  /// poster art is vivid, and at full strength the sheet stops reading as paper
  /// and starts reading as coloured card.
  static const double kHuePush = 0.15;

  /// Stock for a title, nudged toward its artwork so the sheet agrees with what
  /// is printed on it without a rail turning into twenty different colours.
  ///
  /// The push moves **hue only**. Mixing cream and artwork colour as RGB was the
  /// obvious implementation and the wrong one: complementary colours cancel on
  /// the way past grey, so a blue poster did not tint the stock, it bleached it
  /// — 0.22 of saturation gone, paper turned to card. Holding saturation and
  /// lightness at the warm stock's own values keeps it recognisably one paper.
  static Color paperFor(Color? dominant) {
    if (dominant == null) return kWarmPaper;
    final art = HSLColor.fromColor(dominant);
    // Near-neutral artwork has no hue worth borrowing, and asking for one
    // yields whatever rounding noise the decoder left behind.
    if (art.saturation < 0.15) return kWarmPaper;
    final base = HSLColor.fromColor(kWarmPaper);
    // Shortest way round the wheel, so cream never travels through green to
    // reach a magenta poster.
    final delta = ((art.hue - base.hue + 540) % 360) - 180;
    return base.withHue((base.hue + delta * kHuePush + 360) % 360).toColor();
  }

  /// Print wash: desaturated, blacks lifted off true black, so the image reads
  /// as absorbed into stock rather than emitted by a screen.
  static const ColorFilter wash = ColorFilter.matrix(<double>[
    0.72, 0.20, 0.05, 0, 18, //
    0.10, 0.78, 0.09, 0, 16, //
    0.08, 0.18, 0.71, 0, 12, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  State<TexturedArtwork> createState() => _TexturedArtworkState();
}

class _TexturedArtworkState extends State<TexturedArtwork> {
  _Sheet? _sheet;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(TexturedArtwork old) {
    super.didUpdateWidget(old);
    if (old.texture != widget.texture) _resolve();
  }

  Future<void> _resolve() async {
    final sheet = await _Sheet.load(widget.texture);
    if (mounted) setState(() => _sheet = sheet);
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    // Until the stock is decoded the artwork prints plain. Showing nothing
    // would flash a hole in the rail on every cold start.
    if (!widget.enabled || sheet == null) return widget.child;

    // The ink: washed, grained, then gnawed back so paper shows around it.
    Widget out = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: sheet.ink,
      child: ShaderMask(
        blendMode: BlendMode.softLight,
        shaderCallback: sheet.grain,
        child: ColorFiltered(
          colorFilter: TexturedArtwork.wash,
          child: widget.child,
        ),
      ),
    );

    // Paper behind it, carrying the same fibre so the two read as one object.
    out = Stack(
      fit: StackFit.expand,
      children: [
        ShaderMask(
          blendMode: BlendMode.softLight,
          shaderCallback: sheet.grain,
          child: ColoredBox(color: widget.paper),
        ),
        out,
      ],
    );

    // The outer tear, last, so it cuts ink and paper together and nothing can
    // hang past the torn edge.
    out = ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: sheet.stock,
      child: out,
    );

    final shadow = widget.shadow;
    if (shadow == null) return out;
    return Stack(
      // The shadow is offset and blurred, so it necessarily falls outside the
      // artwork box. Clipping it back to that box would restore the straight
      // edge the tear exists to destroy.
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Transform.translate(
            offset: shadow.offset,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: shadow.blurRadius / 2,
                sigmaY: shadow.blurRadius / 2,
              ),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: sheet.stock,
                child: ColoredBox(color: shadow.color),
              ),
            ),
          ),
        ),
        out,
      ],
    );
  }
}

/// A decoded stock sheet plus the shaders drawn from it.
///
/// Decoding is shared across every tile using the same texture — a rail asks
/// for this once per poster, and decoding a 800x1200 sheet twenty times over
/// would cost more than the effect is worth.
class _Sheet {
  _Sheet(this._grain, this._stock);

  final ui.Image _grain;

  /// [_grain] with its alpha widened, so the sheet outlives the ink.
  final ui.Image _stock;

  static final Map<String, Future<_Sheet>> _cache = <String, Future<_Sheet>>{};

  static Future<_Sheet> load(String key) =>
      _cache.putIfAbsent(key, () => _decode(key));

  static Future<_Sheet> _decode(String key) async {
    final data = await rootBundle.load(key);
    final image = await _image(data.buffer.asUint8List());
    return _Sheet(image, await _widenAlpha(image));
  }

  static Future<ui.Image> _image(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// Pushes alpha toward opaque so partly-worn stock counts as intact. 2.2 is
  /// the ratio between the ink and sheet thresholds the assets were baked at.
  static Future<ui.Image> _widenAlpha(ui.Image src) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImage(
      src,
      Offset.zero,
      Paint()
        ..colorFilter = const ColorFilter.matrix(<double>[
          1, 0, 0, 0, 0, //
          0, 1, 0, 0, 0, //
          0, 0, 1, 0, 0, //
          0, 0, 0, 2.2, 0, //
        ]),
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(src.width, src.height);
    picture.dispose();
    return out;
  }

  Shader grain(Rect bounds) => _shader(_grain, bounds);
  Shader ink(Rect bounds) => _shader(_grain, bounds);
  Shader stock(Rect bounds) => _shader(_stock, bounds);

  /// Covers [bounds] with one copy of the sheet, centred. These textures are
  /// framed sheets with a worn border, not tiles — repeating one would stamp
  /// that border across the surface in a grid.
  Shader _shader(ui.Image image, Rect bounds) {
    final scale = (bounds.width / image.width) > (bounds.height / image.height)
        ? bounds.width / image.width
        : bounds.height / image.height;
    final matrix = Matrix4.identity()
      ..translateByDouble(
        bounds.left + (bounds.width - image.width * scale) / 2,
        bounds.top + (bounds.height - image.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    return ui.ImageShader(
      image,
      TileMode.clamp,
      TileMode.clamp,
      matrix.storage,
    );
  }
}

/// The dominant colour of artwork, for [TexturedArtwork.paperFor].
///
/// Decoded at 16x16 because that is all a dominant colour needs, and because a
/// rail asks this of every tile at once. Held against the URL so scrolling back
/// to a title does not decode it twice.
class ArtworkPalette {
  ArtworkPalette._();

  static final Map<String, Color?> _cache = <String, Color?>{};

  static Color? cached(String url) => _cache[url];

  static Future<Color?> dominant(String url, Uint8List bytes) async {
    if (_cache.containsKey(url)) return _cache[url];
    Color? result;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 16,
        targetHeight: 16,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();
      codec.dispose();
      if (data != null) result = _pick(data.buffer.asUint8List());
    } catch (_) {
      // A palette is a nicety; artwork that will not decode still prints on the
      // default stock rather than taking the tile down with it.
      result = null;
    }
    _cache[url] = result;
    return result;
  }

  /// The most saturated band, not the mean. Averaging poster art reliably
  /// produces mud, because complementary colours cancel; the point is to find
  /// what the artwork is *about*.
  static Color? _pick(Uint8List rgba) {
    var bestScore = -1.0;
    Color? best;
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 128) continue;
      final c = Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
      final hsl = HSLColor.fromColor(c);
      // Mid lightness scores highest: near-black and near-white carry no hue.
      final score = hsl.saturation * (1 - (hsl.lightness - 0.5).abs() * 2);
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }
}
