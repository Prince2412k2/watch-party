import 'package:flutter/widgets.dart';

/// The crumpled-paper sheets, one of which is laid over each piece of artwork.
///
/// Seven rather than one because a rail shows twenty posters at once, and a
/// single sheet repeated across all of them stops reading as paper and starts
/// reading as a filter — the eye finds the repeat immediately when the same
/// fold lands in the same place on every tile.
abstract final class ArtworkTexture {
  static const List<String> creases = <String>[
    'assets/textures/crease/1.png',
    'assets/textures/crease/2.png',
    'assets/textures/crease/3.png',
    'assets/textures/crease/4.png',
    'assets/textures/crease/5.png',
    'assets/textures/crease/6.png',
    'assets/textures/crease/7.png',
  ];

  /// The sheet for [seed], chosen so a given title always creases the same way.
  ///
  /// Stable on purpose: a poster that re-folds itself every time it scrolls
  /// back into view is more distracting than no texture at all. A null or empty
  /// seed takes the first sheet rather than a random one, for the same reason —
  /// a tile must not flicker between sheets while its id is still arriving.
  static String creaseFor(String? seed) {
    if (seed == null || seed.isEmpty) return creases.first;
    var hash = 0;
    for (var i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7fffffff;
    }
    return creases[hash % creases.length];
  }
}

/// Artwork on crumpled stock: a photographed sheet — folds, creases and all —
/// laid over the image, with the print slightly washed so the two read as one
/// object rather than as a picture with a filter on top.
///
/// ## What this deliberately is not
///
/// An earlier version tore the artwork's edges away with a mask baked from a
/// grunge texture's luminance. It worked and it looked wrong. The source tear
/// was a halftone dot screen, so at rail size the ragged edge read as a printed
/// pattern rather than a rip; and the paper behind it survived the tear as a
/// hard pale rectangle, which the eye took for the poster's real edge. These
/// sheets are photographs of actual crumpled paper carrying their own alpha, so
/// nothing is derived, masked or thresholded — the sheet is simply laid on top.
///
/// Because nothing is torn, the artwork is still a rectangle, so the frame,
/// edge light and cast shadow drawn around it all still describe the shape that
/// is really there.
class TexturedArtwork extends StatelessWidget {
  const TexturedArtwork({
    super.key,
    required this.child,
    this.seed,
    this.enabled = true,
  });

  /// The artwork to print.
  final Widget child;

  /// Picks which sheet this artwork gets — an item id, typically. See
  /// [ArtworkTexture.creaseFor] for why it is stable rather than random.
  final String? seed;

  /// Off returns [child] untouched, so a caller can A/B the treatment without
  /// restructuring its tree.
  final bool enabled;

  /// Print wash: slightly desaturated with the blacks lifted off true black, so
  /// the image sits *in* the paper rather than glowing through it. Gentle on
  /// purpose — the poster is the one thing on the stage whose job is to sell
  /// the title, and a heavy wash costs more in legibility than it buys in
  /// atmosphere.
  static const ColorFilter wash = ColorFilter.matrix(<double>[
    0.86, 0.11, 0.03, 0, 6, //
    0.05, 0.90, 0.05, 0, 5, //
    0.04, 0.09, 0.87, 0, 4, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      // `passthrough`, not `expand`. This wraps two very differently shaped
      // callers: the backdrop arrives with tight constraints and must fill
      // them, while a poster sits in a Column and arrives with unbounded
      // height, which `expand` turns into an infinite-height assertion.
      fit: StackFit.passthrough,
      children: [
        ColorFiltered(colorFilter: wash, child: child),
        Positioned.fill(
          child: Image.asset(
            ArtworkTexture.creaseFor(seed),
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            gaplessPlayback: true,
          ),
        ),
      ],
    );
  }
}
