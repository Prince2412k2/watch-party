// Browsing interaction core — the parts of the analog stage model that must
// behave identically in Flutter and React.
//
// Ported verbatim from app/client/src/analog/browseCore.ts. Both ports are
// driven by app/shared/design/interaction.json, so a change to one that isn't
// mirrored in the other fails the other language's suite.
//
// Everything here is pure: no widgets, no timers. Callers own the clock and
// feed `atMs` in.

import 'dart:math' as math;

// ── stepped scroll ──────────────────────────────────────────────────────────
//
// "Each deliberate gesture moves one item; momentum is absorbed so focus never
// coasts past the intended item." (analog-interface-reference.md)
//
// Wheel and trackpad hardware emit wildly different event streams: a notched
// mouse wheel sends a few large deltas, a trackpad flick sends dozens of small
// decaying ones. Mapping raw delta to focus movement makes the trackpad
// unusable, so deltas are accumulated to a threshold and the inertia tail is
// discarded.

class SteppedScrollConfig {
  const SteppedScrollConfig({
    this.stepThresholdPx = 48,
    this.gestureIdleMs = 140,
    this.stepCooldownMs = 110,
    this.inertiaFloorPx = 8,
  });

  /// Accumulated delta needed to move focus one item.
  final double stepThresholdPx;

  /// Silence long enough to count as the end of a gesture.
  final double gestureIdleMs;

  /// Floor for the minimum wall time between two steps.
  final double stepCooldownMs;

  /// Deltas at or below this, after a step, are the momentum tail.
  final double inertiaFloorPx;
}

const SteppedScrollConfig kSteppedScrollDefaults = SteppedScrollConfig();

class SteppedScrollState {
  double accumPx = 0;
  double? lastEventAtMs;
  double? lastStepAtMs;

  /// Sign of the gesture in progress: -1, 0 or 1.
  int direction = 0;
}

/// Feed one wheel/trackpad event. Returns the focus movement it produces:
/// `-1`, `0` or `+1` — never more than one item per event, which is what stops
/// a fast flick from coasting.
///
/// Mutates [state] in place, matching the TypeScript original so the fixture
/// scripts read identically in both languages.
int steppedScroll(
  SteppedScrollState state,
  double deltaPx,
  double atMs, [
  SteppedScrollConfig config = kSteppedScrollDefaults,
]) {
  // A gap in the event stream ends the gesture: nothing carries over.
  final lastEvent = state.lastEventAtMs;
  if (lastEvent != null && atMs - lastEvent >= config.gestureIdleMs) {
    state.accumPx = 0;
    state.direction = 0;
  }
  state.lastEventAtMs = atMs;

  if (deltaPx == 0) return 0;

  final sign = deltaPx > 0 ? 1 : -1;
  // A deliberate reverse restarts accumulation rather than cancelling out
  // against travel already spent in the other direction.
  if (state.direction != 0 && sign != state.direction) state.accumPx = 0;
  state.direction = sign;

  // The decaying tail of a flick, after the gesture has already scored a step.
  if (deltaPx.abs() <= config.inertiaFloorPx && state.lastStepAtMs != null) {
    return 0;
  }

  state.accumPx += deltaPx;
  if (state.accumPx.abs() < config.stepThresholdPx) return 0;

  // Threshold reached but the previous step is too recent: hold at the line
  // instead of banking the excess, so a burst can't discharge as a run of steps.
  final lastStep = state.lastStepAtMs;
  if (lastStep != null && atMs - lastStep < config.stepCooldownMs) {
    state.accumPx = sign * config.stepThresholdPx;
    return 0;
  }

  state.accumPx = 0;
  state.lastStepAtMs = atMs;
  return sign;
}

// ── focus restoration ───────────────────────────────────────────────────────
//
// "Back returns to the exact browsing position and focused item."
//
// The interesting cases are the ones where "exact" is no longer available: the
// item was removed from the shelf, or the shelf itself is gone. Both happen
// routinely here — Continue Watching reorders as you watch, and Downloads
// empties. Focus has to land somewhere sensible and deterministic.

class FocusPosition {
  const FocusPosition({required this.shelfId, required this.itemId});

  final String shelfId;
  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is FocusPosition && other.shelfId == shelfId && other.itemId == itemId;

  @override
  int get hashCode => Object.hash(shelfId, itemId);

  @override
  String toString() => 'FocusPosition($shelfId/$itemId)';
}

/// The shelves currently on screen, in display order.
class ShelfSnapshot {
  const ShelfSnapshot({required this.shelfId, required this.itemIds});

  final String shelfId;
  final List<String> itemIds;
}

enum FocusRestoreKind {
  /// The remembered shelf and item both still exist.
  exact,

  /// The shelf survived but the item did not; focus lands by index.
  nearest,

  /// The shelf is gone (or nothing was remembered); focus lands on the default.
  defaultPosition,

  /// Nothing focusable exists at all.
  empty;

  /// The wire spelling used in app/shared/design/interaction.json.
  String get wireName => this == FocusRestoreKind.defaultPosition ? 'default' : name;
}

class FocusRestoreResult {
  const FocusRestoreResult(this.kind, this.position);

  final FocusRestoreKind kind;
  final FocusPosition? position;
}

typedef FocusMemory = Map<String, FocusPosition>;

FocusMemory rememberFocus(FocusMemory memory, String surfaceId, FocusPosition position) =>
    {...memory, surfaceId: position};

FocusMemory forgetFocus(FocusMemory memory, String surfaceId) =>
    {...memory}..remove(surfaceId);

/// Resolve where focus should land when returning to a surface.
///
/// [rememberedIndex] is the index the item held when it was remembered; it is
/// what makes the "item removed" case land next to where the user was rather
/// than at the start of the shelf.
FocusRestoreResult restoreFocus(
  FocusMemory memory,
  String surfaceId,
  List<ShelfSnapshot> shelves, [
  int rememberedIndex = 0,
]) {
  ShelfSnapshot? firstFocusable;
  for (final shelf in shelves) {
    if (shelf.itemIds.isNotEmpty) {
      firstFocusable = shelf;
      break;
    }
  }

  final fallback = firstFocusable == null
      ? const FocusRestoreResult(FocusRestoreKind.empty, null)
      : FocusRestoreResult(
          FocusRestoreKind.defaultPosition,
          FocusPosition(shelfId: firstFocusable.shelfId, itemId: firstFocusable.itemIds.first),
        );

  final remembered = memory[surfaceId];
  if (remembered == null) return fallback;

  ShelfSnapshot? shelf;
  for (final candidate in shelves) {
    if (candidate.shelfId == remembered.shelfId) {
      shelf = candidate;
      break;
    }
  }
  if (shelf == null || shelf.itemIds.isEmpty) return fallback;

  if (shelf.itemIds.contains(remembered.itemId)) {
    return FocusRestoreResult(
      FocusRestoreKind.exact,
      FocusPosition(shelfId: shelf.shelfId, itemId: remembered.itemId),
    );
  }

  // The item went away. Hold the index — clamped into the shortened shelf — so
  // focus stays where the user's attention was.
  final index = math.max(0, math.min(rememberedIndex, shelf.itemIds.length - 1));
  return FocusRestoreResult(
    FocusRestoreKind.nearest,
    FocusPosition(shelfId: shelf.shelfId, itemId: shelf.itemIds[index]),
  );
}

// ── season artwork fallback ─────────────────────────────────────────────────
//
// "season poster -> series poster -> fixed neutral season placeholder"
//
// React and Flutter must derive this from the same Jellyfin season item
// contract rather than each maintaining its own metadata-provider behaviour.
// The placeholder is fixed-size on purpose: layout and focus must not move
// when artwork is missing.

class SeasonArtworkInput {
  const SeasonArtworkInput({
    required this.seasonId,
    required this.seasonNumber,
    required this.seasonImageTag,
    required this.seriesId,
    required this.seriesImageTag,
    this.failedIds = const [],
  });

  final String seasonId;
  final int? seasonNumber;

  /// Jellyfin `ImageTags.Primary` on the season item, when it has its own art.
  final String? seasonImageTag;
  final String seriesId;
  final String? seriesImageTag;

  /// Image ids already known to have failed to load, so a retry can't loop.
  final List<String> failedIds;
}

enum SeasonArtworkKind { season, series, placeholder }

class SeasonArtwork {
  const SeasonArtwork({
    required this.kind,
    required this.itemId,
    required this.imageTag,
    required this.label,
  });

  final SeasonArtworkKind kind;

  /// Jellyfin item id to request Primary art for; null for the placeholder.
  final String? itemId;
  final String? imageTag;

  /// Text the placeholder shows, e.g. "S3". Null unless kind is placeholder.
  final String? label;
}

SeasonArtwork resolveSeasonArtwork(SeasonArtworkInput input) {
  final failed = input.failedIds.toSet();

  final seasonTag = input.seasonImageTag;
  if (seasonTag != null && seasonTag.isNotEmpty && !failed.contains(input.seasonId)) {
    return SeasonArtwork(
      kind: SeasonArtworkKind.season,
      itemId: input.seasonId,
      imageTag: seasonTag,
      label: null,
    );
  }

  final seriesTag = input.seriesImageTag;
  if (seriesTag != null && seriesTag.isNotEmpty && !failed.contains(input.seriesId)) {
    return SeasonArtwork(
      kind: SeasonArtworkKind.series,
      itemId: input.seriesId,
      imageTag: seriesTag,
      label: null,
    );
  }

  final number = input.seasonNumber;
  return SeasonArtwork(
    kind: SeasonArtworkKind.placeholder,
    itemId: null,
    imageTag: null,
    label: number == null ? '—' : 'S$number',
  );
}
