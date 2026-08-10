// The Shows stage is the Movies stage for series, minus the mode strip.
//
// What is worth pinning is exactly that sentence: that the fixed-cursor rule
// holds here too, that the wheel works away from the rail, and that the strip
// is gone rather than reduced to one position.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/widgets/analog_poster.dart';
import 'package:watchparty/app/screens/shows_stage.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';

LibraryItem _show(int i) => LibraryItem(
  id: 'show-$i',
  name: 'Show $i',
  type: 'Series',
  productionYear: 2000 + i,
  overview: 'Overview of show $i.',
  genres: const ['Drama'],
);

final _shows = [for (var i = 0; i < 12; i++) _show(i)];

class _Api extends MockApiClient {
  @override
  String imageUrl(
    String itemId, {
    ImageType type = ImageType.primary,
    String? tag,
  }) => '/image/$itemId/${type.name}';
}

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_Api()),
        browseByTypeProvider(
          BrowseTypeFilter.series,
        ).overrideWith((ref) => Stream.value(_shows)),
        for (final s in _shows)
          itemDetailProvider(s.id).overrideWith((ref) => Stream.value(s)),
      ],
      child: const MaterialApp(home: Scaffold(body: ShowsStage())),
    ),
  );
  await tester.pumpAndSettle();
}

/// Top-left of the poster tile carrying [label] as its caption.
Offset _posterAt(WidgetTester tester, String label) => tester.getTopLeft(
  find
      .ancestor(of: find.text(label), matching: find.byType(AnalogPosterTile))
      .first,
);

/// One wheel notch over [location], with an explicit timestamp so the shared
/// cooldown is exercised deliberately rather than by whatever the clock did.
Future<void> _wheel(
  WidgetTester tester,
  Offset location,
  double delta, {
  required Duration at,
}) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(location, timeStamp: at));
  await tester.sendEventToBinding(
    pointer.scroll(Offset(0, delta), timeStamp: at),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('there is no Singles/Collections strip', (tester) async {
    await _pump(tester);

    // A show has no franchise axis. The strip is removed rather than shown
    // with one position, which would be a control that cannot move.
    expect(find.text('Singles'), findsNothing);
    expect(find.text('Collections'), findsNothing);
  });

  testWidgets('the selected show is the heading and the first poster', (
    tester,
  ) async {
    await _pump(tester);

    // Heading on top, caption in the rail — the Movies stage's arrangement.
    expect(find.text('Show 0'), findsWidgets);
    expect(find.text('Overview of show 0.'), findsOneWidget);
  });

  testWidgets('the cursor holds its position while the row slides', (
    tester,
  ) async {
    await _pump(tester);
    final cursorX = _posterAt(tester, 'Show 0').dx;

    for (var expected = 1; expected <= 4; expected++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(
        _posterAt(tester, 'Show $expected').dx,
        moreOrLessEquals(cursorX, epsilon: 0.5),
        reason:
            'show $expected must slide into the cursor slot, rather than '
            'the cursor moving to it',
      );
      // The copy follows the cursor, exactly as it does on Movies.
      expect(find.text('Overview of show $expected.'), findsOneWidget);
    }
  });

  testWidgets('scrolling over the bare backdrop drives the rail', (
    tester,
  ) async {
    await _pump(tester);
    final cursorX = _posterAt(tester, 'Show 0').dx;

    // Near the top of the stage — nowhere near the rail. The rail is the only
    // thing here that scrolls, so a dead zone over the backdrop would be a
    // bug rather than a boundary.
    await _wheel(
      tester,
      const Offset(900, 120),
      60,
      at: const Duration(milliseconds: 500),
    );

    expect(
      _posterAt(tester, 'Show 1').dx,
      moreOrLessEquals(cursorX, epsilon: 0.5),
      reason: 'one notch anywhere on the stage steps the rail once',
    );
  });

  testWidgets('the search line narrows the rail, and Escape gives it back', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'Show 1');
    await tester.pumpAndSettle();

    // Substring, so 1, 10 and 11 all survive — and nothing else does.
    expect(find.text('Show 1'), findsWidgets);
    expect(find.text('Show 10'), findsOneWidget);
    expect(find.text('Show 2'), findsNothing);
    // The cursor went back to the top of the new list, so the copy is the first
    // match rather than whatever index 0 used to be.
    expect(find.text('Overview of show 1.'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Show 2'), findsOneWidget);
    expect(find.text('Overview of show 0.'), findsOneWidget);
  });

  testWidgets('a search that matches nothing says so', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    // Not "No shows in this library" — the library is fine, the query is not.
    expect(find.text('Nothing matches “zzz”'), findsOneWidget);
  });

  testWidgets('up and down do nothing — there is no second axis', (
    tester,
  ) async {
    await _pump(tester);
    final cursorX = _posterAt(tester, 'Show 0').dx;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();

    expect(
      _posterAt(tester, 'Show 0').dx,
      moreOrLessEquals(cursorX, epsilon: 0.5),
    );
    expect(find.text('Overview of show 0.'), findsOneWidget);
  });
}
