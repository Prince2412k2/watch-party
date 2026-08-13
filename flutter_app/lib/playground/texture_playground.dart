import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/widgets/artwork_wall.dart';
import '../ui/widgets/textured_artwork.dart';
import 'pasted_poster_shader.dart';

/// How the paste is rendered.
///
/// Both are kept so they can be compared directly. The soft-light path is what
/// the app ships: cheap, but it can only shade — it has no way to bend the
/// print over a bump, because a blend mode moves colour and never samples
/// anywhere but straight down. The shader derives a normal from the depth
/// gradient and can displace, light and stain in one pass.
enum PasteMode { shader, softLight }

/// Every number the texture treatment has, in one object.
///
/// Held as a value rather than read off the constants so the playground can
/// move them, and printed by [asDart] in exactly the shape the real source
/// expects — the point of the tool is to end with values that can be pasted
/// somewhere, not with a screenshot and a memory of roughly what looked right.
@immutable
class TextureSettings {
  const TextureSettings({
    this.wall = 0,
    this.sheet = 0,
    this.reliefStrength = ArtworkWall.kReliefStrength,
    this.backdropStrength = ArtworkWall.kBackdropPasteStrength,
    this.posterStrength = ArtworkWall.kPasteStrength,
    this.tintOpacity = ArtworkWall.kTintOpacity,
    this.brightness = ArtworkWall.kReliefBrightness,
    this.contrast = ArtworkWall.kReliefContrast,
    this.posterPaper = ArtworkTexture.kPosterPaperOpacity,
    this.backdropPaper = ArtworkTexture.kBackdropPaperOpacity,
    this.washAmount = ArtworkTexture.kWashAmount,
    this.showBackdrop = true,
    this.mode = PasteMode.shader,
    this.shader = const PasteShaderSettings(),
  });

  final int wall;
  final int sheet;
  final double reliefStrength;
  final double backdropStrength;
  final double posterStrength;
  final double tintOpacity;
  final double brightness;
  final double contrast;
  final double posterPaper;
  final double backdropPaper;
  final double washAmount;
  /// The backdrop is full-bleed, so it covers the wall completely. Hiding it
  /// is the only way to see what the wall controls are doing — and it is also
  /// the app's real no-selection state, so it is worth looking at anyway.
  final bool showBackdrop;
  final PasteMode mode;
  final PasteShaderSettings shader;

  TextureSettings copyWith({
    int? wall,
    int? sheet,
    double? reliefStrength,
    double? backdropStrength,
    double? posterStrength,
    double? tintOpacity,
    double? brightness,
    double? contrast,
    double? posterPaper,
    double? backdropPaper,
    double? washAmount,
    bool? showBackdrop,
    PasteMode? mode,
    PasteShaderSettings? shader,
  }) => TextureSettings(
    wall: wall ?? this.wall,
    sheet: sheet ?? this.sheet,
    reliefStrength: reliefStrength ?? this.reliefStrength,
    backdropStrength: backdropStrength ?? this.backdropStrength,
    posterStrength: posterStrength ?? this.posterStrength,
    tintOpacity: tintOpacity ?? this.tintOpacity,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    posterPaper: posterPaper ?? this.posterPaper,
    backdropPaper: backdropPaper ?? this.backdropPaper,
    washAmount: washAmount ?? this.washAmount,
    showBackdrop: showBackdrop ?? this.showBackdrop,
    mode: mode ?? this.mode,
    shader: shader ?? this.shader,
  );

  /// The wash, dialled between "no wash at all" and the shipped matrix, so the
  /// slider has a defined meaning at both ends rather than being an arbitrary
  /// nudge of nine coefficients.
  ColorFilter get wash => TexturedArtwork.washAt(washAmount);

  String _n(double v) => v.toStringAsFixed(3);

  /// The settings as source, ready to paste over the real constants.
  String asDart() =>
      '''
// lib/ui/widgets/artwork_wall.dart — ArtworkWall
static const double kReliefStrength = ${_n(reliefStrength)};
static const double kBackdropPasteStrength = ${_n(backdropStrength)};
static const double kPasteStrength = ${_n(posterStrength)};
static const double kTintOpacity = ${_n(tintOpacity)};

// lib/ui/widgets/textured_artwork.dart — ArtworkTexture
static const double kPosterPaperOpacity = ${_n(posterPaper)};
static const double kBackdropPaperOpacity = ${_n(backdropPaper)};
static const double kWashAmount = ${_n(washAmount)};

// lib/ui/widgets/artwork_wall.dart — ArtworkWall
static const double kReliefBrightness = ${_n(brightness)};
static const double kReliefContrast = ${_n(contrast)};

// Previewed on wall $wall, sheet $sheet, mode ${mode.name}.

${mode == PasteMode.shader ? shader.asDart() : ''}''';
}

/// A stage built out of the real widgets, so what is tuned here is what ships.
class TexturePlayground extends StatefulWidget {
  const TexturePlayground({super.key});

  @override
  State<TexturePlayground> createState() => _TexturePlaygroundState();
}

class _TexturePlaygroundState extends State<TexturePlayground> {
  var _s = const TextureSettings();
  final _artPath = TextEditingController();
  String? _art;

  @override
  void dispose() {
    _artPath.dispose();
    super.dispose();
  }

  void _set(TextureSettings next) => setState(() => _s = next);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _s.asDart()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Values copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Row(
        children: [
          Expanded(child: _Preview(settings: _s, artPath: _art)),
          SizedBox(
            width: 340,
            child: _Panel(
              settings: _s,
              onChanged: _set,
              onCopy: _copy,
              artPath: _artPath,
              onArt: (v) => setState(() => _art = v.isEmpty ? null : v),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wall, pasted backdrop, and a rail of posters — the three surfaces the
/// treatment lands on, at roughly the sizes they land at.
///
/// Stateful because the shader path needs decoded [ui.Image]s rather than
/// widgets: a fragment shader takes samplers, so the artwork has to exist as an
/// image before it can be pasted, not as a subtree that paints one.
class _Preview extends StatefulWidget {
  const _Preview({required this.settings, required this.artPath});

  final TextureSettings settings;
  final String? artPath;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  ui.FragmentProgram? _program;
  ui.Image? _wall;
  ui.Image? _depth;
  ui.Image? _paperPortrait;
  ui.Image? _paperLandscape;
  final _art = <int, ui.Image>{};
  String? _artFor;

  static const _colours = [
    Color(0xFF1663EB),
    Color(0xFFB3402A),
    Color(0xFF2F6B4F),
    Color(0xFFD9A521),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_Preview old) {
    super.didUpdateWidget(old);
    if (old.settings.wall != widget.settings.wall) _loadWall();
    if (old.settings.sheet != widget.settings.sheet) _loadPaper();
    if (old.artPath != widget.artPath) _loadArt();
  }

  Future<void> _load() async {
    _program = await PasteShader.load();
    await _loadWall();
    await _loadPaper();
    await _loadArt();
  }

  Future<void> _loadWall() async {
    final i = widget.settings.wall;
    // Raw, not eased: the shader does its own arithmetic on the depth and
    // pre-flattening it would leave nothing for the gradient to find.
    final depth = await WallImages.load(ArtworkWall.depth(i));
    final wall = await WallImages.load(ArtworkWall.tint(i));
    if (!mounted || i != widget.settings.wall) return;
    setState(() {
      _depth = depth;
      _wall = wall;
    });
  }

  Future<void> _loadPaper() async {
    final i = widget.settings.sheet;
    final portrait = await WallImages.load(
      ArtworkTexture.sheetAt(i, portrait: true),
    );
    final landscape = await WallImages.load(
      ArtworkTexture.sheetAt(i, portrait: false),
    );
    if (!mounted || i != widget.settings.sheet) return;
    setState(() {
      _paperPortrait = portrait;
      _paperLandscape = landscape;
    });
  }

  Future<void> _loadArt() async {
    final path = widget.artPath;
    _art.clear();
    _artFor = path;
    if (path == null || !File(path).existsSync()) {
      if (mounted) setState(() {});
      return;
    }
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted || path != _artFor) return;
    setState(() {
      for (var i = 0; i < 10; i++) {
        _art[i] = frame.image;
      }
    });
  }

  /// A stand-in poster, drawn once. Strong flat colour and a hard edge, because
  /// real artwork hides most of what is being tuned.
  ui.Image _synthetic(int i, Size size) {
    final cached = _art[i];
    if (cached != null) return cached;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, [
          _colours[i % _colours.length],
          const Color(0xFF15151A),
        ]),
    );
    final para =
        (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: size.width * 0.4))
              ..pushStyle(ui.TextStyle(color: const Color(0x44FFFFFF)))
              ..addText('${i + 1}'))
            .build()
          ..layout(ui.ParagraphConstraints(width: size.width));
    canvas.drawParagraph(para, Offset(0, size.height * 0.3));
    final image = recorder.endRecording().toImageSync(
      size.width.round(),
      size.height.round(),
    );
    _art[i] = image;
    return image;
  }

  Widget _paste({
    required int i,
    required Size size,
    required double softStrength,
    required bool portrait,
  }) {
    final s = widget.settings;
    if (s.mode == PasteMode.shader) {
      return PastedPoster(
        program: _program,
        poster: _synthetic(i, size),
        wall: _wall,
        depth: _depth,
        paper: portrait ? _paperPortrait : _paperLandscape,
        settings: s.shader.copyWith(
          // The two surfaces want different amounts of paper, so the shader
          // takes whichever belongs to the one being drawn.
          paperStrength: portrait ? s.posterPaper : s.backdropPaper,
          wash: s.washAmount,
        ),
      );
    }
    // The shipped path, for comparison.
    return WallLayer(
      index: s.wall,
      strength: softStrength,
      brightness: s.brightness,
      contrast: s.contrast,
      builder: (context, depth, _) => WallRelief(
        depth: depth,
        strength: softStrength,
        child: TexturedArtwork(
          portrait: portrait,
          sheet: ArtworkTexture.sheetAt(s.sheet + i, portrait: portrait),
          opacity: portrait ? s.posterPaper : s.backdropPaper,
          wash: s.wash,
          child: RawImage(image: _synthetic(i, size), fit: BoxFit.cover),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return LayoutBuilder(
      builder: (context, box) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // The wall. Always the soft-light path: it is the surface itself,
            // not something pasted to it, so there is nothing to displace.
            WallLayer(
              index: s.wall,
              withTint: true,
              strength: s.reliefStrength,
              brightness: s.brightness,
              contrast: s.contrast,
              builder: (context, depth, tint) => Stack(
                fit: StackFit.expand,
                children: [
                  WallRelief(
                    depth: depth,
                    strength: s.reliefStrength,
                    child: const ColoredBox(color: Color(0xFF17120F)),
                  ),
                  if (tint != null)
                    Opacity(
                      opacity: s.tintOpacity,
                      child: RawImage(image: tint, fit: BoxFit.cover),
                    ),
                ],
              ),
            ),
            // Full-bleed, as it is in the app. Which means it covers the wall
            // completely — so it can be hidden, or every wall control would
            // look dead with nothing to show for it.
            if (s.showBackdrop)
              _paste(
                i: 0,
                size: const Size(1280, 720),
                softStrength: s.backdropStrength,
                portrait: false,
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 40,
              height: 300,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 40),
                itemCount: 8,
                separatorBuilder: (_, _) => const SizedBox(width: 22),
                itemBuilder: (context, i) => SizedBox(
                  width: 200,
                  child: _paste(
                    i: i + 1,
                    size: const Size(400, 600),
                    softStrength: s.posterStrength,
                    portrait: true,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.settings,
    required this.onChanged,
    required this.onCopy,
    required this.artPath,
    required this.onArt,
  });

  final TextureSettings settings;
  final ValueChanged<TextureSettings> onChanged;
  final VoidCallback onCopy;
  final TextEditingController artPath;
  final ValueChanged<String> onArt;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    return Container(
      color: const Color(0xFF1B1B1F),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
              children: [
                const _Head('Source'),
                _Step(
                  label: 'Wall',
                  value: s.wall,
                  max: ArtworkWall.count - 1,
                  onChanged: (v) => onChanged(s.copyWith(wall: v)),
                ),
                _Step(
                  label: 'Paper sheet',
                  value: s.sheet,
                  max: ArtworkTexture.count - 1,
                  onChanged: (v) => onChanged(s.copyWith(sheet: v)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: artPath,
                  onChanged: onArt,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Artwork file (optional)',
                    labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
                    hintText: '/path/to/a/poster.jpg',
                    hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                  ),
                ),

                const _Head('Mode'),
                // Scaled down rather than left to overflow: the panel is a
                // fixed 340 and the two labels do not fit at default metrics.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<PasteMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: PasteMode.shader,
                        label: Text('Shader'),
                      ),
                      ButtonSegment(
                        value: PasteMode.softLight,
                        label: Text('Soft-light'),
                      ),
                    ],
                    selected: {s.mode},
                    onSelectionChanged: (v) =>
                        onChanged(s.copyWith(mode: v.first)),
                  ),
                ),

                const _Head('View'),
                // A plain Row, not a SwitchListTile: the panel is a ColoredBox
                // and a ListTile paints its ink on the nearest Material, which
                // the box would hide — Flutter asserts on exactly that.
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Show backdrop',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Full-bleed, so it hides the wall',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: s.showBackdrop,
                      onChanged: (v) => onChanged(s.copyWith(showBackdrop: v)),
                    ),
                  ],
                ),
                if (s.mode == PasteMode.shader) ...[
                  const _Head('Shader'),
                  _Slide(
                    label: 'Displacement',
                    value: s.shader.displacement,
                    max: 0.08,
                    onChanged: (v) => onChanged(
                      s.copyWith(shader: s.shader.copyWith(displacement: v)),
                    ),
                  ),
                  _Slide(
                    label: 'Wall grain through paper',
                    value: s.shader.textureStrength,
                    max: 0.6,
                    onChanged: (v) => onChanged(
                      s.copyWith(shader: s.shader.copyWith(textureStrength: v)),
                    ),
                  ),
                  _Slide(
                    label: 'Bump strength',
                    value: s.shader.bumpStrength,
                    max: 40,
                    onChanged: (v) => onChanged(
                      s.copyWith(shader: s.shader.copyWith(bumpStrength: v)),
                    ),
                  ),
                  _Slide(
                    label: 'Light angle',
                    value: s.shader.lightAngle,
                    max: 6.283,
                    onChanged: (v) => onChanged(
                      s.copyWith(shader: s.shader.copyWith(lightAngle: v)),
                    ),
                  ),
                  _Slide(
                    label: 'Light depth',
                    value: s.shader.lightDepth,
                    min: 0.1,
                    max: 4,
                    onChanged: (v) => onChanged(
                      s.copyWith(shader: s.shader.copyWith(lightDepth: v)),
                    ),
                  ),
                  _Slide(
                    label: 'Ambient',
                    value: s.shader.ambient,
                    max: 1.5,
                    onChanged: (v) => onChanged(
                      s.copyWith(shader: s.shader.copyWith(ambient: v)),
                    ),
                  ),
                  _Slide(
                    label: 'Gain',
                    value: s.shader.gain,
                    max: 2,
                    onChanged: (v) => onChanged(
                      s.copyWith(shader: s.shader.copyWith(gain: v)),
                    ),
                  ),
                  _Slide(
                    label: 'Sample spread',
                    value: s.shader.sampleSpread,
                    min: 0.5,
                    max: 8,
                    onChanged: (v) => onChanged(
                      s.copyWith(shader: s.shader.copyWith(sampleSpread: v)),
                    ),
                  ),
                ],

                const _Head('Relief'),
                _Slide(
                  label: 'Wall strength',
                  value: s.reliefStrength,
                  onChanged: (v) => onChanged(s.copyWith(reliefStrength: v)),
                ),
                _Slide(
                  label: 'Backdrop strength',
                  value: s.backdropStrength,
                  onChanged: (v) => onChanged(s.copyWith(backdropStrength: v)),
                ),
                _Slide(
                  label: 'Poster strength',
                  value: s.posterStrength,
                  onChanged: (v) => onChanged(s.copyWith(posterStrength: v)),
                ),
                _Slide(
                  label: 'Brightness',
                  value: s.brightness,
                  min: -0.5,
                  max: 0.5,
                  onChanged: (v) => onChanged(s.copyWith(brightness: v)),
                ),
                _Slide(
                  label: 'Contrast',
                  value: s.contrast,
                  min: 0.2,
                  max: 3,
                  onChanged: (v) => onChanged(s.copyWith(contrast: v)),
                ),

                const _Head('Paper & wall colour'),
                _Slide(
                  label: 'Poster paper (noise & grunge)',
                  value: s.posterPaper,
                  onChanged: (v) => onChanged(s.copyWith(posterPaper: v)),
                ),
                _Slide(
                  label: 'Backdrop paper',
                  value: s.backdropPaper,
                  onChanged: (v) => onChanged(s.copyWith(backdropPaper: v)),
                ),
                _Slide(
                  label: 'Print wash',
                  value: s.washAmount,
                  onChanged: (v) => onChanged(s.copyWith(washAmount: v)),
                ),
                _Slide(
                  label: 'Wall tint opacity',
                  value: s.tintOpacity,
                  max: 0.5,
                  onChanged: (v) => onChanged(s.copyWith(tintOpacity: v)),
                ),

              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy values'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => onChanged(const TextureSettings()),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 4),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          // Flexed and ellipsised: 'Wall grain through paper' plus its value
          // does not fit a fixed 340 panel, and an unflexed Row overflows
          // rather than wrapping.
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value.toStringAsFixed(3),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      SliderTheme(
        data: SliderThemeData(
          trackHeight: 2,
          overlayShape: SliderComponentShape.noOverlay,
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ),
    ],
  );
}

class _Step extends StatelessWidget {
  const _Step({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.remove, size: 16, color: Colors.white70),
        onPressed: () => onChanged((value - 1) % (max + 1)),
      ),
      SizedBox(
        width: 26,
        child: Text(
          '$value',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
      IconButton(
        icon: const Icon(Icons.add, size: 16, color: Colors.white70),
        onPressed: () => onChanged((value + 1) % (max + 1)),
      ),
    ],
  );
}
