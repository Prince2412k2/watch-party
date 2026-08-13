import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/widgets/artwork_wall.dart';
import '../ui/widgets/textured_artwork.dart';

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
    this.brightness = 0,
    this.contrast = 1,
    this.paperOpacity = 1,
    this.washAmount = 1,
    this.backdropInset = 0.045,
  });

  final int wall;
  final int sheet;
  final double reliefStrength;
  final double backdropStrength;
  final double posterStrength;
  final double tintOpacity;
  final double brightness;
  final double contrast;
  final double paperOpacity;
  final double washAmount;
  final double backdropInset;

  TextureSettings copyWith({
    int? wall,
    int? sheet,
    double? reliefStrength,
    double? backdropStrength,
    double? posterStrength,
    double? tintOpacity,
    double? brightness,
    double? contrast,
    double? paperOpacity,
    double? washAmount,
    double? backdropInset,
  }) => TextureSettings(
    wall: wall ?? this.wall,
    sheet: sheet ?? this.sheet,
    reliefStrength: reliefStrength ?? this.reliefStrength,
    backdropStrength: backdropStrength ?? this.backdropStrength,
    posterStrength: posterStrength ?? this.posterStrength,
    tintOpacity: tintOpacity ?? this.tintOpacity,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    paperOpacity: paperOpacity ?? this.paperOpacity,
    washAmount: washAmount ?? this.washAmount,
    backdropInset: backdropInset ?? this.backdropInset,
  );

  /// The wash, dialled between "no wash at all" and the shipped matrix, so the
  /// slider has a defined meaning at both ends rather than being an arbitrary
  /// nudge of nine coefficients.
  ColorFilter get wash {
    if (washAmount >= 1) return TexturedArtwork.defaultWash;
    const shipped = <double>[
      0.86, 0.11, 0.03, 0, 6, //
      0.05, 0.90, 0.05, 0, 5, //
      0.04, 0.09, 0.87, 0, 4, //
      0, 0, 0, 1, 0, //
    ];
    const identity = <double>[
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
    return ColorFilter.matrix(<double>[
      for (var i = 0; i < 20; i++)
        identity[i] + (shipped[i] - identity[i]) * washAmount,
    ]);
  }

  String _n(double v) => v.toStringAsFixed(3);

  /// The settings as source, ready to paste over the real constants.
  String asDart() =>
      '''
// lib/ui/widgets/artwork_wall.dart — ArtworkWall
static const double kReliefStrength = ${_n(reliefStrength)};
static const double kBackdropPasteStrength = ${_n(backdropStrength)};
static const double kPasteStrength = ${_n(posterStrength)};
static const double kTintOpacity = ${_n(tintOpacity)};

// lib/analog/widgets/analog_stage.dart — AnalogStage
static const double kPasteInset = ${_n(backdropInset)};

// Relief tuning, passed to WallLayer(brightness:, contrast:).
// Currently WallLayer defaults to brightness 0 / contrast 1; thread these
// through the two call sites in analog_stage.dart and analog_poster.dart.
//   brightness: ${_n(brightness)}
//   contrast:   ${_n(contrast)}

// Paper: TexturedArtwork(opacity:) — currently defaults to 1.
//   opacity: ${_n(paperOpacity)}
//   wash amount: ${_n(washAmount)}  (1.0 = the shipped matrix, 0 = none)

// Previewed on wall $wall, sheet $sheet.
''';
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
class _Preview extends StatelessWidget {
  const _Preview({required this.settings, required this.artPath});

  final TextureSettings settings;
  final String? artPath;

  Widget _art(int i) {
    final path = artPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(File(path), fit: BoxFit.cover);
    }
    // Something with strong flat colour and a hard edge, so the relief and the
    // paper are both obvious. Real artwork hides a lot of what is being tuned.
    const colours = [
      Color(0xFF1663EB),
      Color(0xFFB3402A),
      Color(0xFF2F6B4F),
      Color(0xFFD9A521),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colours[i % colours.length], const Color(0xFF15151A)],
        ),
      ),
      child: Center(
        child: Text(
          '${i + 1}',
          style: const TextStyle(
            fontSize: 64,
            fontWeight: FontWeight.w900,
            color: Color(0x33FFFFFF),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final inset = box.biggest.shortestSide * settings.backdropInset;
        return Stack(
          fit: StackFit.expand,
          children: [
            // The wall.
            WallLayer(
              index: settings.wall,
              withTint: true,
              strength: settings.reliefStrength,
              brightness: settings.brightness,
              contrast: settings.contrast,
              builder: (context, depth, tint) => Stack(
                fit: StackFit.expand,
                children: [
                  WallRelief(
                    depth: depth,
                    strength: settings.reliefStrength,
                    child: const ColoredBox(color: Color(0xFF17120F)),
                  ),
                  if (tint != null)
                    Opacity(
                      opacity: settings.tintOpacity,
                      child: RawImage(image: tint, fit: BoxFit.cover),
                    ),
                ],
              ),
            ),
            // The backdrop, pasted.
            Padding(
              padding: EdgeInsets.all(inset),
              child: WallLayer(
                index: settings.wall,
                strength: settings.backdropStrength,
                brightness: settings.brightness,
                contrast: settings.contrast,
                builder: (context, depth, _) => WallRelief(
                  depth: depth,
                  strength: settings.backdropStrength,
                  child: TexturedArtwork(
                    portrait: false,
                    sheet: ArtworkTexture.sheetAt(
                      settings.sheet,
                      portrait: false,
                    ),
                    opacity: settings.paperOpacity,
                    wash: settings.wash,
                    child: _art(0),
                  ),
                ),
              ),
            ),
            // A rail of posters across it, so the courses can be checked for
            // continuity from one tile to the next.
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
                  child: WallLayer(
                    index: settings.wall,
                    strength: settings.posterStrength,
                    brightness: settings.brightness,
                    contrast: settings.contrast,
                    builder: (context, depth, _) => WallRelief(
                      depth: depth,
                      strength: settings.posterStrength,
                      child: TexturedArtwork(
                        sheet: ArtworkTexture.sheetAt(
                          settings.sheet + i,
                          portrait: true,
                        ),
                        opacity: settings.paperOpacity,
                        wash: settings.wash,
                        child: _art(i + 1),
                      ),
                    ),
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
                  label: 'Paper opacity',
                  value: s.paperOpacity,
                  onChanged: (v) => onChanged(s.copyWith(paperOpacity: v)),
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

                const _Head('Layout'),
                _Slide(
                  label: 'Backdrop inset',
                  value: s.backdropInset,
                  max: 0.2,
                  onChanged: (v) => onChanged(s.copyWith(backdropInset: v)),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
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
