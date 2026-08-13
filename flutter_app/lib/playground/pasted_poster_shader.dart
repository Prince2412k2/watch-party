import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Everything `shaders/pasted_poster.frag` takes, in declaration order.
///
/// Order is the contract: `setFloat` indexes a flat list of floats, so a vec2
/// eats two slots and inserting a uniform anywhere but the end silently
/// reassigns every one after it. [_bind] is written to be read next to the
/// shader's uniform block, top to bottom.
@immutable
class PasteShaderSettings {
  const PasteShaderSettings({
    this.displacement = 0.015,
    this.textureStrength = 0.12,
    this.bumpStrength = 8,
    this.lightAngle = 3.66,
    this.lightDepth = 1,
    this.ambient = 0.82,
    this.gain = 1.12,
    this.sampleSpread = 1,
  });

  /// How far the print slides down a slope, as a fraction of the quad.
  final double displacement;

  /// How much wall grain shows through the paper. Small: push it up and the
  /// poster stops reading as paper and starts reading as transparent.
  final double textureStrength;

  /// How steep the normal derived from the depth gradient is.
  final double bumpStrength;

  /// Light direction, radians. 0 is from the right, increasing anticlockwise.
  final double lightAngle;

  /// The light's z. Low is raking and harsh, high is flat and frontal.
  final double lightDepth;

  /// Brightness of a fully unlit patch, and of a fully lit one.
  final double ambient;
  final double gain;

  /// Distance between the gradient's samples, in wall pixels. Above 1 this
  /// smooths mortar joints into rolling swells rather than sharp steps.
  final double sampleSpread;

  PasteShaderSettings copyWith({
    double? displacement,
    double? textureStrength,
    double? bumpStrength,
    double? lightAngle,
    double? lightDepth,
    double? ambient,
    double? gain,
    double? sampleSpread,
  }) => PasteShaderSettings(
    displacement: displacement ?? this.displacement,
    textureStrength: textureStrength ?? this.textureStrength,
    bumpStrength: bumpStrength ?? this.bumpStrength,
    lightAngle: lightAngle ?? this.lightAngle,
    lightDepth: lightDepth ?? this.lightDepth,
    ambient: ambient ?? this.ambient,
    gain: gain ?? this.gain,
    sampleSpread: sampleSpread ?? this.sampleSpread,
  );

  String _n(double v) => v.toStringAsFixed(3);

  String asDart() =>
      '''
// shaders/pasted_poster.frag — uniforms
displacement:    ${_n(displacement)}
textureStrength: ${_n(textureStrength)}
bumpStrength:    ${_n(bumpStrength)}
lightAngle:      ${_n(lightAngle)}   // radians
lightDepth:      ${_n(lightDepth)}
ambient:         ${_n(ambient)}
gain:            ${_n(gain)}
sampleSpread:    ${_n(sampleSpread)}
''';
}

/// Loads the paste shader once.
///
/// One program, reused. Compiling it per frame — or per poster — is the mistake
/// the Flutter docs warn about, and with twenty tiles on a rail it would be
/// twenty compilations a frame.
class PasteShader {
  PasteShader._();

  static Future<ui.FragmentProgram>? _program;

  static Future<ui.FragmentProgram> load() =>
      _program ??= ui.FragmentProgram.fromAsset('shaders/pasted_poster.frag');

  @visibleForTesting
  static void debugClear() => _program = null;
}

/// Paints [poster] as if it were stuck to the wall behind it.
///
/// [origin] is where this quad sits in the window, and it is the reason the
/// effect holds together: the wall and its depth are sampled in window space,
/// so the courses run out of one poster, across the wall, and into the next.
/// Sampling in the quad's own space would give every poster its own private
/// brick starting in its own corner.
class PastedPosterPainter extends CustomPainter {
  PastedPosterPainter({
    required this.program,
    required this.poster,
    required this.wall,
    required this.depth,
    required this.origin,
    required this.window,
    required this.settings,
  });

  final ui.FragmentProgram program;
  final ui.Image poster;
  final ui.Image wall;
  final ui.Image depth;
  final Offset origin;
  final Size window;
  final PasteShaderSettings settings;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || window.isEmpty) return;
    final shader = program.fragmentShader();
    var i = 0;
    void f(double v) => shader.setFloat(i++, v);

    f(size.width);
    f(size.height);
    f(origin.dx);
    f(origin.dy);
    f(window.width);
    f(window.height);
    f(settings.displacement);
    f(settings.textureStrength);
    f(settings.bumpStrength);
    f(settings.lightAngle);
    f(settings.lightDepth);
    f(settings.ambient);
    f(settings.gain);
    f(settings.sampleSpread);

    shader
      ..setImageSampler(0, poster)
      ..setImageSampler(1, wall)
      ..setImageSampler(2, depth);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    shader.dispose();
  }

  @override
  bool shouldRepaint(PastedPosterPainter old) =>
      old.poster != poster ||
      old.wall != wall ||
      old.depth != depth ||
      old.origin != origin ||
      old.window != window ||
      old.settings != settings ||
      old.program != program;
}

/// A quad painted through the paste shader, which reports its own position in
/// the window so the wall can be sampled there.
///
/// The offset is read after layout rather than passed in, because nothing above
/// this knows it: a poster's place on screen depends on how far its rail has
/// scrolled. It is read in a post-frame callback and fed back as state, so the
/// first frame paints at the previous offset and every frame after is correct —
/// acceptable here, where the alternative is a custom render object and this is
/// a tuning tool.
class PastedPoster extends StatefulWidget {
  const PastedPoster({
    super.key,
    required this.poster,
    required this.wall,
    required this.depth,
    required this.settings,
    required this.program,
  });

  final ui.Image? poster;
  final ui.Image? wall;
  final ui.Image? depth;
  final PasteShaderSettings settings;
  final ui.FragmentProgram? program;

  @override
  State<PastedPoster> createState() => _PastedPosterState();
}

class _PastedPosterState extends State<PastedPoster> {
  Offset _origin = Offset.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(PastedPoster old) {
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
  Widget build(BuildContext context) {
    final program = widget.program;
    final poster = widget.poster;
    final wall = widget.wall;
    final depth = widget.depth;
    if (program == null || poster == null || wall == null || depth == null) {
      // Plain artwork until everything has arrived. A hole on the stage while
      // a shader compiles is worse than a poster that gains its texture late.
      return poster == null
          ? const SizedBox.expand()
          : RawImage(image: poster, fit: BoxFit.cover);
    }
    return CustomPaint(
      painter: PastedPosterPainter(
        program: program,
        poster: poster,
        wall: wall,
        depth: depth,
        origin: _origin,
        window: MediaQuery.sizeOf(context),
        settings: widget.settings,
      ),
      size: Size.infinite,
    );
  }
}
