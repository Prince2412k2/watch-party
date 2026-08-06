import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/analog.dart';

const _surface = 'browse:movie';

ShelfSnapshot _shelf(String id, List<String> items) =>
    ShelfSnapshot(shelfId: id, itemIds: items);

void main() {
  late ProviderContainer container;
  late AnalogFocusNotifier focus;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    focus = container.read(analogFocusProvider.notifier);
  });

  test('nothing remembered lands on the first focusable item', () {
    final result = focus.restore(_surface, [
      _shelf('all', const ['a', 'b', 'c']),
    ]);
    expect(result.kind, FocusRestoreKind.defaultPosition);
    expect(result.position?.itemId, 'a');
  });

  test('a remembered item that still exists is restored exactly', () {
    focus.remember(
      _surface,
      const FocusPosition(shelfId: 'all', itemId: 'c'),
      2,
    );
    final result = focus.restore(_surface, [
      _shelf('all', const ['a', 'b', 'c']),
    ]);
    expect(result.kind, FocusRestoreKind.exact);
    expect(result.position?.itemId, 'c');
  });

  test('a removed item holds its index in the shortened shelf', () {
    focus.remember(
      _surface,
      const FocusPosition(shelfId: 'all', itemId: 'c'),
      2,
    );
    // Continue Watching reorders as you watch; this is the shape of that.
    final result = focus.restore(_surface, [
      _shelf('all', const ['a', 'b', 'd', 'e']),
    ]);
    expect(result.kind, FocusRestoreKind.nearest);
    expect(result.position?.itemId, 'd');
  });

  test('the remembered index is clamped into a much shorter shelf', () {
    focus.remember(
      _surface,
      const FocusPosition(shelfId: 'all', itemId: 'j'),
      9,
    );
    final result = focus.restore(_surface, [
      _shelf('all', const ['a', 'b']),
    ]);
    expect(result.kind, FocusRestoreKind.nearest);
    expect(result.position?.itemId, 'b');
  });

  test('a vanished shelf falls back to the first focusable one', () {
    focus.remember(
      _surface,
      const FocusPosition(shelfId: 'genre:Noir', itemId: 'x'),
      1,
    );
    final result = focus.restore(_surface, [
      _shelf('empty', const []),
      _shelf('all', const ['a', 'b']),
    ]);
    expect(result.kind, FocusRestoreKind.defaultPosition);
    expect(result.position, const FocusPosition(shelfId: 'all', itemId: 'a'));
  });

  test('an emptied surface reports empty rather than guessing', () {
    focus.remember(
      _surface,
      const FocusPosition(shelfId: 'downloads', itemId: 'x'),
      0,
    );
    // Downloads empties; there is nothing to focus and nothing to invent.
    final result = focus.restore(_surface, [_shelf('downloads', const [])]);
    expect(result.kind, FocusRestoreKind.empty);
    expect(result.position, isNull);
  });

  test('surfaces do not leak into each other, and forget clears both maps', () {
    focus.remember(
      'browse:movie',
      const FocusPosition(shelfId: 'all', itemId: 'c'),
      2,
    );
    focus.remember(
      'browse:series',
      const FocusPosition(shelfId: 'all', itemId: 'a'),
      0,
    );
    expect(
      focus.restore('browse:series', [
        _shelf('all', const ['a', 'b', 'c']),
      ]).position?.itemId,
      'a',
    );

    focus.forget('browse:movie');
    expect(container.read(analogFocusProvider).memory.containsKey('browse:movie'), isFalse);
    expect(container.read(analogFocusProvider).indices.containsKey('browse:movie'), isFalse);
    expect(
      focus.restore('browse:movie', [
        _shelf('all', const ['a', 'b', 'c']),
      ]).kind,
      FocusRestoreKind.defaultPosition,
    );
  });
}
