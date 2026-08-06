import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/analog.dart';
import 'package:watchparty/ui/analog_tokens.dart';

import '../square_artwork.dart';

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(backgroundColor: AnalogColor.stageGround, body: Center(child: child)),
  ),
);

void main() {
  group('square-artwork invariant', () {
    testWidgets('holds at rest, focused, and with no artwork', (tester) async {
      for (final focused in [false, true]) {
        await tester.pumpWidget(
          _host(
            AnalogPosterTile(
              title: 'Blade Runner',
              width: 160,
              focused: focused,
              onTap: () {},
            ),
          ),
        );
        await tester.pump(AnalogMotion.focusStepMs);
        expectSquareArtwork(tester, find.byType(AnalogPosterTile));
      }
    });

    testWidgets('holds on the placeholder', (tester) async {
      await tester.pumpWidget(
        _host(const AnalogPosterTile(placeholderLabel: 'S3', width: 160)),
      );
      expect(find.text('S3'), findsOneWidget);
      expectSquareArtwork(tester, find.byType(AnalogPosterTile));
    });

    testWidgets('holds on the loading skeleton', (tester) async {
      await tester.pumpWidget(
        _host(const AnalogPosterSkeleton(width: 160)),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expectSquareArtwork(tester, find.byType(AnalogPosterSkeleton));
      // Guard the guard: the walker has to actually catch a rounded tile, or
      // every assertion above passes vacuously.
      await tester.pumpWidget(
        _host(
          Container(
            key: const ValueKey('rounded'),
            width: 160,
            height: 240,
            decoration: BoxDecoration(
              color: AnalogColor.stageSurface,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
      var caught = false;
      try {
        expectSquareArtwork(tester, find.byKey(const ValueKey('rounded')));
      } on TestFailure {
        caught = true;
      }
      expect(caught, isTrue);
    });
  });

  testWidgets('artwork is 2:3, not the old 3/5', (tester) async {
    await tester.pumpWidget(
      _host(const AnalogPosterTile(width: 200, title: 'Dune')),
    );
    final art = tester.getSize(find.byType(AnalogPosterPlaceholder));
    expect(art.width, 200);
    expect(art.height, 300);
    expect(art.height / art.width, AnalogPoster.aspectH / AnalogPoster.aspectW);
    expect(AnalogPosterTile.artHeightFor(200), 300);
  });

  testWidgets('focus lifts and grows the artwork without tilting it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AnalogPosterTile(width: 160, focused: false)),
    );
    final rest = tester.getRect(find.byType(AnalogPosterPlaceholder));

    await tester.pumpWidget(
      _host(const AnalogPosterTile(width: 160, focused: true)),
    );
    await tester.pumpAndSettle();
    final focused = tester.getRect(find.byType(AnalogPosterPlaceholder));

    expect(
      focused.width / rest.width,
      closeTo(AnalogSelection.focusScale, 0.01),
    );
    // Lift is upward: the focused centre sits above the resting one by the
    // lift, and the box is not skewed (equal growth on both sides).
    expect(
      rest.center.dy - focused.center.dy,
      closeTo(AnalogSelection.focusLiftPx, 0.5),
    );
    expect(focused.center.dx, closeTo(rest.center.dx, 0.5));
  });

  group('season artwork fallback', () {
    const seriesId = 'series-1';
    String url(String itemId, String? tag) => '/api/image/$itemId?tag=$tag';

    Future<AnalogPosterTile> pumpSeason(
      WidgetTester tester,
      SeasonArtworkInput input,
    ) async {
      await tester.pumpWidget(
        _host(
          AnalogSeasonPoster(
            input: input,
            imageUrlBuilder: url,
            width: 120,
            title: 'Season',
          ),
        ),
      );
      return tester.widget<AnalogPosterTile>(find.byType(AnalogPosterTile));
    }

    testWidgets('uses the season item Primary when it has one', (tester) async {
      final tile = await pumpSeason(
        tester,
        const SeasonArtworkInput(
          seasonId: 'season-3',
          seasonNumber: 3,
          seasonImageTag: 'seasontag',
          seriesId: seriesId,
          seriesImageTag: 'seriestag',
        ),
      );
      // Crucially a Jellyfin item id, so the URL is same-origin. The old path
      // read Sonarr's `seasons[].images`, which is a third-party CDN host that
      // ArtworkCache._fetch refuses outright.
      expect(tile.imageUrl, '/api/image/season-3?tag=seasontag');
    });

    testWidgets('falls back to the series Primary', (tester) async {
      final tile = await pumpSeason(
        tester,
        const SeasonArtworkInput(
          seasonId: 'season-3',
          seasonNumber: 3,
          seasonImageTag: null,
          seriesId: seriesId,
          seriesImageTag: 'seriestag',
        ),
      );
      expect(tile.imageUrl, '/api/image/$seriesId?tag=seriestag');
    });

    testWidgets('falls back to a fixed placeholder carrying the season number', (
      tester,
    ) async {
      final tile = await pumpSeason(
        tester,
        const SeasonArtworkInput(
          seasonId: 'season-3',
          seasonNumber: 3,
          seasonImageTag: null,
          seriesId: seriesId,
          seriesImageTag: null,
        ),
      );
      expect(tile.imageUrl, isNull);
      expect(tile.placeholderLabel, 'S3');
      expect(find.text('S3'), findsOneWidget);
      expectSquareArtwork(tester, find.byType(AnalogPosterTile));
    });

    testWidgets('a known-failed image is skipped rather than retried', (
      tester,
    ) async {
      final tile = await pumpSeason(
        tester,
        const SeasonArtworkInput(
          seasonId: 'season-3',
          seasonNumber: 3,
          seasonImageTag: 'seasontag',
          seriesId: seriesId,
          seriesImageTag: 'seriestag',
          failedIds: ['season-3'],
        ),
      );
      expect(tile.imageUrl, '/api/image/$seriesId?tag=seriestag');
    });

    testWidgets('the placeholder keeps the layout the artwork would have', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          AnalogSeasonPoster(
            input: const SeasonArtworkInput(
              seasonId: 'season-9',
              seasonNumber: 9,
              seasonImageTag: null,
              seriesId: seriesId,
              seriesImageTag: null,
            ),
            imageUrlBuilder: url,
            width: 120,
          ),
        ),
      );
      // "keep a fixed-size neutral placeholder with the season number so
      // layout and focus do not move".
      final box = tester.getSize(find.byType(AnalogPosterPlaceholder));
      expect(box.height / box.width, closeTo(3 / 2, 0.02));
    });
  });
}
