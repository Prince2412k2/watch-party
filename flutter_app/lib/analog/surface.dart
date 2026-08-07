// Focus persistence across a surface change.
//
// "Back returns to the exact browsing position and focused item." [restoreFocus]
// in browse_core.dart decides *which* item that is, driven by the shared
// fixture. This file is the surface-shaped layer around it: naming a surface so
// two browsing levels do not share one memory, describing the shelves in the
// shape the core wants, and turning the core's id answer back into the indices
// a shelf renders from.
//
// The port's one deliberate divergence from the web's surface.ts: there, the
// memory is a module-level global, because a surface unmounts entirely when you
// drill into a title and component state cannot be what remembers. Here that
// role is already filled by `analogFocusProvider` (focus_memory.dart), which
// outlives any widget for the same reason and is testable without a reset hook.
// So this file carries no mutable state at all.

import 'browse_core.dart';

/// One level of the browse stack — a library view, a collection, a series.
class StackLevel {
  const StackLevel({this.id, this.name, this.type});

  final String? id;
  final String? name;
  final String? type;

  @override
  bool operator ==(Object other) =>
      other is StackLevel &&
      other.id == id &&
      other.name == name &&
      other.type == type;

  @override
  int get hashCode => Object.hash(id, name, type);

  @override
  String toString() => 'StackLevel($id, $name, $type)';
}

/// A stable name for "where the user is".
///
/// Includes the drill-down path, so the top of Movies and a collection inside it
/// each keep their own focus rather than the deeper one overwriting the
/// shallower one on the way back out.
String surfaceId(String tab, [List<StackLevel> stack = const []]) {
  final path = <String>[
    for (final level in stack)
      if (level.id != null) level.id!,
  ];
  return path.isEmpty ? tab : '$tab/${path.join('/')}';
}

ShelfSnapshot shelfSnapshot(String shelfId, List<String> itemIds) =>
    ShelfSnapshot(shelfId: shelfId, itemIds: itemIds);

/// Where focus lands when a surface comes back, in the indices a shelf renders
/// from.
class FocusPlan {
  const FocusPlan({
    required this.kind,
    required this.shelfIndex,
    required this.itemIndex,
  });

  final FocusRestoreKind kind;

  /// -1 when there is nothing focusable on the surface.
  final int shelfIndex;
  final int itemIndex;

  @override
  bool operator ==(Object other) =>
      other is FocusPlan &&
      other.kind == kind &&
      other.shelfIndex == shelfIndex &&
      other.itemIndex == itemIndex;

  @override
  int get hashCode => Object.hash(kind, shelfIndex, itemIndex);

  @override
  String toString() => 'FocusPlan(${kind.wireName}, $shelfIndex, $itemIndex)';
}

const FocusPlan emptyFocusPlan = FocusPlan(
  kind: FocusRestoreKind.empty,
  shelfIndex: -1,
  itemIndex: -1,
);

/// Resolve a [FocusRestoreResult] into shelf/item indices.
///
/// [rememberedIndex] is the index the item held when it was last seen, and it is
/// what makes a removed item land next to where the user's attention was rather
/// than at the start of the shelf.
FocusPlan focusPlan(
  FocusMemory memory,
  String id,
  List<ShelfSnapshot> shelves, [
  int rememberedIndex = 0,
]) {
  final result = restoreFocus(memory, id, shelves, rememberedIndex);
  final position = result.position;
  if (position == null) return emptyFocusPlan;

  final shelfIndex = shelves.indexWhere(
    (shelf) => shelf.shelfId == position.shelfId,
  );
  if (shelfIndex < 0) return emptyFocusPlan;

  final itemIndex = shelves[shelfIndex].itemIds.indexOf(position.itemId);
  if (itemIndex < 0) return emptyFocusPlan;

  return FocusPlan(
    kind: result.kind,
    shelfIndex: shelfIndex,
    itemIndex: itemIndex,
  );
}
