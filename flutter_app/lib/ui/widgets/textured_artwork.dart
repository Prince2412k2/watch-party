import 'package:flutter/widgets.dart';

/// The crumpled-paper sheets, one of which is laid over each piece of artwork.
///
/// Seven rather than one because a rail shows twenty posters at once, and a
/// single sheet repeated across all of them stops reading as paper and starts
/// reading as a filter — the eye finds the repeat immediately when the same
/// fold lands in the same place on every tile.
abstract final class ArtworkTexture {
  static const int count = 10;

  /// How strongly the paper's noise and grunge is laid over a poster.
  ///
  /// Separate from [kBackdropPaperOpacity] because the two want different
  /// amounts and always did: a poster is a small sheet you look straight at,
  /// where the grain is most of what says "paper", while the backdrop is
  /// scenery already carrying the wall's relief and a scrim on top of that.
  /// One shared number could only ever be wrong for one of them.
  static const double kPosterPaperOpacity = 1.000;

  /// The same for the backdrop, off by default — the grunge is wanted on the
  /// posters, not on the sheet behind them.
  static const double kBackdropPaperOpacity = 0.0;

  /// How far the print wash is dialled in, 0 = none, 1 = the full matrix.
  static const double kWashAmount = 1.000;

  /// The nth sheet of a kind, for a caller that wants to name one directly
  /// rather than derive it from a title.
  static String sheetAt(int index, {required bool portrait}) {
    final kind = portrait ? 'portrait' : 'landscape';
    return 'assets/textures/paper/$kind-'
        '${(index % count).abs().toString().padLeft(2, '0')}.png';
  }

  /// Paper cut to the shape it is printed on: tall sheets for posters, wide
  /// ones for the backdrop. Using one for both would stretch a sheet's grain
  /// and edge wear along whichever axis it was scaled on, which is exactly the
  /// sort of thing the eye reads as "filter" rather than "paper".
  static String sheetFor(String? seed, {required bool portrait}) =>
      sheetAt(_index(seed), portrait: portrait);

  /// Stable on purpose: a poster that re-creases every time it scrolls back
  /// into view is more distracting than no texture at all. A null or empty seed
  /// takes the first sheet rather than a random one, for the same reason — a
  /// tile must not flicker between sheets while its id is still arriving.
  static int _index(String? seed) {
    if (seed == null || seed.isEmpty) return 0;
    var hash = 0;
    for (var i = 0; i < seed.length; i++) {
      hash = (hash * 31 + seed.codeUnitAt(i)) & 0x7fffffff;
    }
    return hash % count;
  }
}

/// Switches the paper off for everything beneath it.
///
/// An inherited scope rather than a parameter threaded down from the screens,
/// because the widgets that draw artwork live in `analog/`, which is kept free
/// of providers on purpose — a rail, a shelf and a stage would each have to
/// carry a flag they have no other use for, through call sites that only exist
/// to pass it on. One wrap at the root reaches all of them.
///
/// Absent, artwork keeps its texture: the default belongs with the treatment,
/// not with whoever remembered to install the scope.
class ArtworkTextureScope extends InheritedWidget {
  const ArtworkTextureScope({
    super.key,
    required this.enabled,
    required super.child,
    this.wallSeed,
  });

  final bool enabled;

  /// Which wall this room is papered with. Carried here rather than passed down
  /// because every poster needs it and none of them are near the screen that
  /// knows it — and because a poster on a different wall from the stage behind
  /// it would break the continuity the whole effect rests on.
  final String? wallSeed;

  static ArtworkTextureScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ArtworkTextureScope>();

  static bool of(BuildContext context) => _of(context)?.enabled ?? true;

  static String? wallSeedOf(BuildContext context) => _of(context)?.wallSeed;

  @override
  bool updateShouldNotify(ArtworkTextureScope old) =>
      old.enabled != enabled || old.wallSeed != wallSeed;
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
    this.enabled,
    this.portrait = true,
    this.sheet,
    this.opacity = 1,
    this.wash,
  });

  /// The artwork to print.
  final Widget child;

  /// Picks which sheet this artwork gets — an item id, typically. See
  /// [ArtworkTexture.sheetFor] for why it is stable rather than random.
  final String? seed;

  /// Tall paper for a poster, wide paper for a backdrop.
  final bool portrait;

  /// An explicit sheet, overriding the one [seed] would pick. For tuning, where
  /// the point is to compare sheets rather than to keep one stable.
  final String? sheet;

  /// How strongly the sheet is laid on.
  final double opacity;

  /// The print wash. Null takes the shipped amount; exposed so it can be tuned
  /// against real artwork.
  final ColorFilter? wash;

  /// Off returns [child] untouched. Null — the usual case — defers to the
  /// nearest [ArtworkTextureScope], and so to the user's setting; pass it
  /// explicitly only to force one surface against that.
  final bool? enabled;

  /// The wash at [ArtworkTexture.kWashAmount]. Held rather than rebuilt,
  /// because every tile asks for it on every build.
  static final ColorFilter shippedWash = washAt(ArtworkTexture.kWashAmount);

  /// The wash dialled between none and the full matrix, so both ends of the
  /// control mean something rather than being an arbitrary nudge of nine
  /// coefficients.
  static ColorFilter washAt(double amount) {
    if (amount >= 1) return defaultWash;
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
        identity[i] + (shipped[i] - identity[i]) * amount,
    ]);
  }

  /// Print wash at full strength: slightly desaturated with the blacks lifted
  /// off true black, so the image sits *in* the paper rather than glowing
  /// through it. Gentle on
  /// purpose — the poster is the one thing on the stage whose job is to sell
  /// the title, and a heavy wash costs more in legibility than it buys in
  /// atmosphere.
  static const ColorFilter defaultWash = ColorFilter.matrix(<double>[
    0.86, 0.11, 0.03, 0, 6, //
    0.05, 0.90, 0.05, 0, 5, //
    0.04, 0.09, 0.87, 0, 4, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    if (!(enabled ?? ArtworkTextureScope.of(context))) return child;
    return Stack(
      // `passthrough`, not `expand`. This wraps two very differently shaped
      // callers: the backdrop arrives with tight constraints and must fill
      // them, while a poster sits in a Column and arrives with unbounded
      // height, which `expand` turns into an infinite-height assertion.
      fit: StackFit.passthrough,
      children: [
        ColorFiltered(
          colorFilter: wash ?? TexturedArtwork.shippedWash,
          child: child,
        ),
        Positioned.fill(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Image.asset(
              sheet ?? ArtworkTexture.sheetFor(seed, portrait: portrait),
              fit: BoxFit.cover,
              excludeFromSemantics: true,
              gaplessPlayback: true,
            ),
          ),
        ),
      ],
    );
  }
}
