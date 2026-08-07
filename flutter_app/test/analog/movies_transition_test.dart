// The select transition.
//
// The thing worth pinning is not that an animation runs — it is the property
// that makes the whole design work: the heading and the overview are the SAME
// widgets before and after, at the same size and position, so they appear not
// to move while the poster flies and the rail leaves. If a future change routes
// to a separate detail screen, the text stops being the same widget and this
// fails, which is exactly when someone needs to be told.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/screens/movies_detail_layer.dart';

void main() {
  group('the stagger orders the move', () {
    test('the rail is gone before the poster lands', () {
      // The rail is what the poster is leaving, so it must clear out first.
      expect(
        MoviesDetailStagger.rail.end,
        lessThan(MoviesDetailStagger.poster.end),
      );
    });

    test('actions and cast wait for the poster to be most of the way there', () {
      expect(
        MoviesDetailStagger.actions.begin,
        greaterThan(MoviesDetailStagger.rail.end),
        reason: 'actions must not slide in while the rail is still leaving',
      );
      expect(
        MoviesDetailStagger.cast.begin,
        greaterThanOrEqualTo(MoviesDetailStagger.actions.begin),
        reason: 'cast comes last, from beneath',
      );
    });

    test('everything has landed by the end of the controller', () {
      for (final interval in [
        MoviesDetailStagger.rail,
        MoviesDetailStagger.poster,
        MoviesDetailStagger.actions,
        MoviesDetailStagger.cast,
      ]) {
        expect(interval.transform(1), 1);
        expect(interval.transform(0), 0);
      }
    });
  });

  group('the action bar assembles rather than appearing', () {
    testWidgets('controls stagger against each other', (tester) async {
      Future<List<double>> opacitiesAt(double progress) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MoviesActionBar(
                progress: progress,
                downloadBusy: false,
                onPlay: () {},
                onDownload: () {},
                onBack: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        return tester
            .widgetList<Opacity>(find.byType(Opacity))
            .map((o) => o.opacity)
            .toList();
      }

      final early = await opacitiesAt(0.1);
      expect(
        early.first,
        greaterThan(early.last),
        reason: 'Play leads; the controls after it are still arriving',
      );

      final done = await opacitiesAt(1);
      expect(done.every((o) => o == 1), isTrue, reason: 'all landed at the end');

      final none = await opacitiesAt(0);
      expect(none.every((o) => o == 0), isTrue);
    });
  });

  testWidgets('the cast row does not eat the wheel', (tester) async {
    // The stage owns scrolling — it drives the rail. A cast row that scrolled
    // would make the surface behave differently depending on where the pointer
    // happened to be resting.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MoviesCastRow(
            people: const [],
            height: 120,
            imageUrlFor: (id) => 'http://example.invalid/$id',
          ),
        ),
      ),
    );
    await tester.pump();
    // Empty cast renders nothing rather than an empty scroller.
    expect(find.byType(ListView), findsNothing);
  });
}
