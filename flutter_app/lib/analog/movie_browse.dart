// The Movies stage's browse model: the two modes, the keys that move between
// them, and the collection drill-in.
//
// "We want to add support for movie collections/franchise. The way we have a
// slider for seasons in the show screen, on movies tab will have two options —
// singles and collections. Up down and scroll updown (when not in the movie
// grid) will toggle it. When we click on a collection a show like screen opens
// for that collection."
//
// The mode lives on the browse STACK rather than in widget state, because the
// stack is what back/restore reads: a level restored on its own would otherwise
// sit in Singles looking at a franchise's parts. A browse entry is explicitly
// open-ended and other surfaces already carry extra keys on it.
//
// Pure: no widgets, no fetching. The screen is the only thing that knows a URL.
// This is the Dart half of app/client/src/analog/movieBrowse.ts and is held to
// it by movie_browse_parity_test.dart.

import 'surface.dart';

// ── the two modes ───────────────────────────────────────────────────────────

enum BrowseMode {
  singles,
  collections;

  /// The wire spelling, shared with the web client and the party session.
  String get wireName => name;

  static BrowseMode? fromWire(Object? value) => switch (value) {
    'singles' => BrowseMode.singles,
    'collections' => BrowseMode.collections,
    _ => null,
  };
}

/// Slider order, top to bottom. Up moves towards the first, Down the last.
const List<BrowseMode> browseModes = [BrowseMode.singles, BrowseMode.collections];

const Map<BrowseMode, String> browseModeLabels = {
  BrowseMode.singles: 'Singles',
  BrowseMode.collections: 'Collections',
};

bool isBrowseMode(Object? value) => BrowseMode.fromWire(value) != null;

/// One step of the mode slider.
///
/// Clamped, not wrapping. A two-position slider that wraps is indistinguishable
/// from a toggle, and "controls should feel deterministic" — holding Down must
/// settle on Collections rather than flickering between the two. The same
/// function serves the arrow keys and a stepped scroll, so the two input routes
/// cannot drift.
BrowseMode stepBrowseMode(BrowseMode mode, int direction) {
  final index = browseModes.indexOf(mode);
  final next = index + direction.sign;
  return browseModes[next.clamp(0, browseModes.length - 1)];
}

// ── input intents ───────────────────────────────────────────────────────────

enum StageIntent {
  /// Move the cursor along the rail.
  railPrev,
  railNext,

  /// Move the Singles/Collections slider.
  modePrev,
  modeNext,

  activate,
  back;

  /// The wire spelling used in the shared interaction fixture.
  String get wireName => switch (this) {
    StageIntent.railPrev => 'rail-prev',
    StageIntent.railNext => 'rail-next',
    StageIntent.modePrev => 'mode-prev',
    StageIntent.modeNext => 'mode-next',
    StageIntent.activate => 'activate',
    StageIntent.back => 'back',
  };
}

/// Key → intent for this stage.
///
/// Deliberately NOT the kit's `focusIntentForKey`, which folds Up/Down onto the
/// same track as Left/Right because a kit surface has one shelf that owns focus.
/// This stage has two axes: the rail runs horizontally and the mode slider
/// vertically, exactly as the sketch draws them, so the four arrows are four
/// different movements and a remote's d-pad lands on the same four names.
///
/// Keyed by the web's `KeyboardEvent.key` spellings so both clients read from
/// one table; the screen maps Flutter's [LogicalKeyboardKey] onto these.
StageIntent? stageKeyIntent(String key) => switch (key) {
  'ArrowLeft' => StageIntent.railPrev,
  'ArrowRight' => StageIntent.railNext,
  'ArrowUp' => StageIntent.modePrev,
  'ArrowDown' => StageIntent.modeNext,
  'Enter' || ' ' || 'Spacebar' => StageIntent.activate,
  'Escape' || 'Backspace' => StageIntent.back,
  _ => null,
};

/// The mode step a stepped-scroll result outside the rail produces.
BrowseMode modeForScrollStep(BrowseMode mode, int step) =>
    step == 0 ? mode : stepBrowseMode(mode, step);

// ── the browse stack ────────────────────────────────────────────────────────

/// A stack level, plus the mode the root level carries for followers.
class MovieLevel extends StackLevel {
  const MovieLevel({super.id, super.name, super.type, this.mode});

  final BrowseMode? mode;

  MovieLevel withModeTag(BrowseMode? mode) =>
      MovieLevel(id: id, name: name, type: type, mode: mode);

  @override
  bool operator ==(Object other) =>
      other is MovieLevel &&
      other.id == id &&
      other.name == name &&
      other.type == type &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(id, name, type, mode);

  @override
  String toString() => 'MovieLevel($id, $name, $type, ${mode?.wireName})';
}

/// Jellyfin models a movie collection/franchise as a box set.
const String collectionType = 'BoxSet';

bool isCollection(Object? type) => type == collectionType;

/// A Movies library view, as the root of the stack.
class MoviesView {
  const MoviesView({required this.id, required this.name, this.type});

  final String id;
  final String name;
  final String? type;
}

/// The root of the stack: the Movies library view, tagged with the current mode.
MovieLevel rootLevel(MoviesView view, BrowseMode mode) => MovieLevel(
  id: view.id,
  name: view.name,
  type: view.type ?? 'CollectionFolder',
  mode: mode,
);

MovieLevel? rootOf(List<MovieLevel> stack) =>
    stack.isEmpty ? null : stack.first;

BrowseMode modeFromStack(
  List<MovieLevel> stack, [
  BrowseMode fallback = BrowseMode.singles,
]) => rootOf(stack)?.mode ?? fallback;

/// The collection currently drilled into, or null at the list level.
///
/// Read off the stack rather than held separately so that a guest following a
/// host lands in the same franchise without a second wire field, and so Back is
/// just "pop".
///
/// The type check is what keeps a follower sane when the driver is on an older
/// implementation that pushes a `Movie` level for a title's detail page.
/// Treating that as a franchise would fetch a box set's contents for a movie id
/// and render an empty rail. A level with no type at all is still accepted —
/// the wire allows every field to be absent, and this surface only ever pushes
/// box sets.
MovieLevel? collectionFromStack(List<MovieLevel> stack) {
  if (stack.length < 2) return null;
  final top = stack.last;
  if (top.id == null) return null;
  if (top.type != null && top.type != collectionType) return null;
  return top;
}

/// Switch modes.
///
/// Truncates to the root: a franchise's parts are not a thing Singles can show,
/// so staying drilled in across the switch would leave the rail rendering a
/// collection's contents under a Singles heading.
List<MovieLevel> withMode(List<MovieLevel> stack, BrowseMode mode) {
  final root = rootOf(stack);
  if (root == null) return const [];
  return [root.withModeTag(mode)];
}

/// Enter on a collection: a show-like level for its parts.
List<MovieLevel> openCollection(List<MovieLevel> stack, MovieLevel collection) {
  final root = rootOf(stack);
  if (root == null) return [...stack];
  return [
    root.withModeTag(BrowseMode.collections),
    MovieLevel(
      id: collection.id,
      name: collection.name,
      type: collection.type ?? collectionType,
    ),
  ];
}

/// Back out of a collection to the list it came from.
List<MovieLevel> closeCollection(List<MovieLevel> stack) =>
    stack.length > 1 ? stack.sublist(0, stack.length - 1) : [...stack];

// ── activation ──────────────────────────────────────────────────────────────

/// What Enter/click does to the focused item.
sealed class Activation {
  const Activation();
}

/// Details are already on the stage, so Enter plays — exactly like an episode.
class PlayActivation extends Activation {
  const PlayActivation(this.itemId);

  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is PlayActivation && other.itemId == itemId;

  @override
  int get hashCode => itemId.hashCode;
}

class OpenActivation extends Activation {
  const OpenActivation(this.collection);

  final MovieLevel collection;

  @override
  bool operator ==(Object other) =>
      other is OpenActivation && other.collection == collection;

  @override
  int get hashCode => collection.hashCode;
}

class NoActivation extends Activation {
  const NoActivation();

  @override
  bool operator ==(Object other) => other is NoActivation;

  @override
  int get hashCode => 0;
}

/// Driven by the item's type rather than the current mode: a box set opens
/// wherever it is encountered, and everything else plays. That is the same
/// answer for a single, for a part inside a franchise, and for a box set that
/// turns up in a library listing — one rule instead of three that have to agree.
Activation activationFor({String? id, String? name, String? type}) {
  if (id == null || id.isEmpty) return const NoActivation();
  if (isCollection(type)) {
    return OpenActivation(MovieLevel(id: id, name: name ?? '', type: type));
  }
  return PlayActivation(id);
}

// ── surfaces ────────────────────────────────────────────────────────────────

/// The focus-memory key for where the user is.
///
/// The mode is part of the identity: Singles and Collections are two different
/// lists of two different lengths, and sharing one memory would restore focus in
/// one from a position only the other ever had. [surfaceId] already folds the
/// drill-in path in, which keeps a franchise's position separate from the
/// list's.
String moviesTab(BrowseMode mode) => 'movies:${mode.wireName}';
