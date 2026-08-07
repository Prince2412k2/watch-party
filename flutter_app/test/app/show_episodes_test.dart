// A show's episodes follow the movies rule.
//
// "Selected episode should always be first. It should follow the same rules
// the list of movies follows." So this pins the fixed cursor, the wheel
// regions, and the one thing that genuinely differs from a poster rail — the
// 16:9 crop.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/widgets/analog_poster.dart';
import 'package:watchparty/app/screens/detail_stage.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';

const _series = LibraryItem(
  id: 'series',
  name: 'Signal',
  type: 'Series',
  overview: 'A series synopsis.',
  genres: ['Drama'],
);

LibraryItem _season(int n) => LibraryItem(
  id: 'season-$n',
  name: 'Season $n',
  type: 'Season',
  indexNumber: n,
);

LibraryItem _episode(int season, int number) => LibraryItem(
  id: 'ep-$season-$number',
  name: 'S${season}E$number Title',
  type: 'Episode',
  seriesId: 'series',
  seriesName: 'Signal',
  parentId: 'season-$season',
  parentIndexNumber: season,
  indexNumber: number,
  overview: 'Synopsis of season $season episode $number.',
  runTimeTicks: 30000000000,
);

const _seasons = [1, 2];
final _episodes = {
  for (final s in _seasons) s: [for (var i = 1; i <= 8; i++) _episode(s, i)],
};

class _Api extends MockApiClient {
  @override
  String imageUrl(
    String itemId, {
    ImageType type = ImageType.primary,
    String? tag,
  }) => '/image/$itemId/${type.name}';

  @override
  Future<LibraryItem> item(String id) async {
    if (id == 'series') return _series;
    for (final row in _episodes.values) {
      for (final ep in row) {
        if (ep.id == id) return ep;
      }
    }
    return _series;
  }

  @override
  Future<List<LibraryItem>> children(String itemId) async {
    if (itemId == 'series') return [for (final s in _seasons) _season(s)];
    for (final s in _seasons) {
      if (itemId == 'season-$s') return _episodes[s]!;
    }
    return const [];
  }
}

Future<void> _pump(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(_Api()),
        authProvider.overrideWith((ref) {
          final notifier = AuthNotifier(ref);
          notifier.state = const AuthState(
            user: User(userId: 'u1', name: 'Test User'),
            initialized: true,
          );
          return notifier;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: DetailStage(
            itemId: 'series',
            onWatch: (_, _) {},
            onBack: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _tileOf(String caption) => find
    .ancestor(of: find.text(caption), matching: find.byType(AnalogPosterTile))
    .first;

Offset _stillAt(WidgetTester tester, String caption) =>
    tester.getTopLeft(_tileOf(caption));

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

/// The centre of the seasons column: the aside half of the two-column layout,
/// vertically in the middle where the strip is aligned.
Offset _seasonsRegion(WidgetTester tester) =>
    tester.getCenter(find.text('Season 2'));

void main() {
  testWidgets('a show opens on its first season, with the series copy up', (
    tester,
  ) async {
    await _pump(tester);

    // The rail exists and reads its captions from the episodes.
    expect(find.text('S1E1 Title'), findsWidgets);
    expect(find.text('S1E8 Title'), findsWidgets);
    // Nothing is picked yet, so the show itself is still the subject.
    expect(find.text('A series synopsis.'), findsOneWidget);
  });

  testWidgets('the selected episode is always the first slot', (tester) async {
    await _pump(tester);

    // Land on episode 1 so there is a cursor to measure from.
    await tester.tap(_tileOf('S1E1 Title'));
    await tester.pumpAndSettle();
    final cursorX = _stillAt(tester, 'S1E1 Title').dx;

    for (var n = 2; n <= 5; n++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(
        _stillAt(tester, 'S1E$n Title').dx,
        moreOrLessEquals(cursorX, epsilon: 0.5),
        reason: 'episode $n must travel into the cursor slot — the row moves, '
            'the cursor does not',
      );
    }
  });

  testWidgets('episode stills are 16:9, not 2:3 posters', (tester) async {
    await _pump(tester);

    final tile = tester.widget<AnalogPosterTile>(_tileOf('S1E3 Title'));
    expect(tile.aspectRatio, AnalogPosterTile.stillAspect);
    expect(
      AnalogPosterTile.artHeightFor(160, aspectRatio: tile.aspectRatio),
      moreOrLessEquals(90, epsilon: 0.01),
    );
  });

  testWidgets('the copy follows the episode cursor', (tester) async {
    await _pump(tester);

    await tester.tap(_tileOf('S1E4 Title'));
    await tester.pumpAndSettle();

    // The episode is the subject; the series is the breadcrumb above it.
    expect(find.text('Synopsis of season 1 episode 4.'), findsOneWidget);
    expect(find.text('SIGNAL'), findsOneWidget);
    expect(find.textContaining('S1 E4'), findsOneWidget);
  });

  testWidgets('one wheel notch over the seasons steps exactly one season', (
    tester,
  ) async {
    await _pump(tester);
    // Opens on season 1 — the show's own copy is up until an episode is picked.
    expect(find.text('S1E1 Title'), findsWidgets);

    // The regression this guards: two Listeners on one subtree both handling
    // the signal, so every notch moved two. With only two seasons a double
    // step would run off the end and land back on season 2 — so the assertion
    // is on the episodes actually rendered, which say which season is live.
    await _wheel(
      tester,
      _seasonsRegion(tester),
      60,
      at: const Duration(milliseconds: 500),
    );

    expect(
      find.text('S2E1 Title'),
      findsWidgets,
      reason: 'one notch moves to season 2',
    );
    expect(find.text('S1E1 Title'), findsNothing);

    // And it stops there rather than wrapping.
    await _wheel(
      tester,
      _seasonsRegion(tester),
      60,
      at: const Duration(milliseconds: 1500),
    );
    expect(find.text('S2E1 Title'), findsWidgets);
  });

  testWidgets('the wheel away from the seasons drives the episode rail', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(_tileOf('S1E1 Title'));
    await tester.pumpAndSettle();
    final cursorX = _stillAt(tester, 'S1E1 Title').dx;

    // Over the copy/backdrop, not over the rail and not over the seasons.
    await _wheel(
      tester,
      const Offset(300, 700),
      60,
      at: const Duration(milliseconds: 500),
    );

    expect(
      _stillAt(tester, 'S1E2 Title').dx,
      moreOrLessEquals(cursorX, epsilon: 0.5),
      reason: 'the wheel anywhere but the seasons steps the episodes',
    );
    // The season did not move with it.
    expect(find.text('S2E1 Title'), findsNothing);
  });

  testWidgets('up and down step the season slider', (tester) async {
    await _pump(tester);
    expect(find.text('S1E1 Title'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('S2E1 Title'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('S1E1 Title'), findsWidgets);
  });

  testWidgets('clicking a season selects it', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Season 2'));
    await tester.pumpAndSettle();

    expect(find.text('S2E1 Title'), findsWidgets);
    expect(find.text('S1E1 Title'), findsNothing);
  });
}
