import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browse_core.dart';

/// What the app remembers about where focus was on each browsing surface.
///
/// [indices] is not redundant with [memory]: [restoreFocus] needs the *index*
/// the remembered item held, because that is what lets focus land next to
/// where the user was when the item itself has since been removed — Continue
/// Watching reorders as you watch, Downloads empties.
class AnalogFocusState {
  const AnalogFocusState({this.memory = const {}, this.indices = const {}});

  final FocusMemory memory;
  final Map<String, int> indices;

  AnalogFocusState copyWith({FocusMemory? memory, Map<String, int>? indices}) =>
      AnalogFocusState(
        memory: memory ?? this.memory,
        indices: indices ?? this.indices,
      );
}

/// Per-surface focus memory, backed by the shared [restoreFocus] core.
///
/// "Back returns to the exact browsing position and focused item."
/// (analog-interface-reference.md §Detail model.) Before this, selection lived
/// in a private `int _selectedIndex` inside the shelf's State, so leaving the
/// surface destroyed it and coming back always landed on the first item.
class AnalogFocusNotifier extends StateNotifier<AnalogFocusState> {
  AnalogFocusNotifier() : super(const AnalogFocusState());

  void remember(String surfaceId, FocusPosition position, int index) {
    state = state.copyWith(
      memory: rememberFocus(state.memory, surfaceId, position),
      indices: {...state.indices, surfaceId: index},
    );
  }

  void forget(String surfaceId) {
    state = state.copyWith(
      memory: forgetFocus(state.memory, surfaceId),
      indices: {...state.indices}..remove(surfaceId),
    );
  }

  /// Where focus should land on returning to [surfaceId], given the shelves
  /// that exist right now.
  FocusRestoreResult restore(String surfaceId, List<ShelfSnapshot> shelves) =>
      restoreFocus(
        state.memory,
        surfaceId,
        shelves,
        state.indices[surfaceId] ?? 0,
      );
}

final analogFocusProvider =
    StateNotifierProvider<AnalogFocusNotifier, AnalogFocusState>(
      (ref) => AnalogFocusNotifier(),
    );
