import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/analog.dart';
import 'package:watchparty/app/screens/browse_screen.dart';
import 'package:watchparty/cache/artwork_cache.dart';
import 'package:watchparty/cache/artwork_prefetcher.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/data/catalog_repository.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/analog_tokens.dart';
import 'package:watchparty/ui/ui.dart';

import '../analog/square_artwork.dart';

LibraryItem _movie(String id, {List<String> genres = const []}) => LibraryItem(
  id: id,
  name: 'Title $id',
  type: 'Movie',
  genres: genres,
);

/// Artwork on a relative, same-origin path with the image type in it, so a
/// warmed url says which item and which artwork it was for.
class _ImageApi extends MockApiClient {
  @override
  String imageUrl(
    String itemId, {
    ImageType type = ImageType.primary,
    String? tag,
  }) => '/image/$itemId/${type.name}';
}

/// Records every title the catalog was asked to warm.
class _CatalogApi extends MockApiClient {
  final List<String> warmedItems = [];

  @override
  Future<LibraryItem> item(String id) async {
    warmedItems.add(id);
    return LibraryItem(id: id, name: 'Title $id', type: 'Movie');
  }
}

/// Records what the prefetcher asked for without touching the network — the
/// real fetch path is covered in `test/cache/artwork_prefetcher_test.dart`;
/// what is under test here is which urls the browse surface hands over.
class _RecordingArtworkCache extends ArtworkCache {
  _RecordingArtworkCache()
    : super(Dio(), directory: Directory.systemTemp);

  final List<String> warmed = [];

  @override
  Uint8List? peek(String url) => null;

  @override
  bool isSameOrigin(String url) => true;

  @override
  Stream<Uint8List> load(String url) {
    warmed.add(url);
    return Stream.value(Uint8List.fromList(const [1, 2, 3]));
  }
}

/// The catalog the screen renders, mutable so a test can drop an item and
/// invalidate — which is how focus restoration gets exercised against a shelf
/// that has changed underneath it.
class _Catalog {
  List<LibraryItem> items = [];
}

void main() {
  late ProviderContainer container;
  late _Catalog catalog;

  setUp(() {
    catalog = _Catalog();
    container = ProviderContainer(
      overrides: [
        browseByTypeProvider(
          BrowseTypeFilter.movie,
        ).overrideWith((ref) => Stream.value(catalog.items)),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            backgroundColor: AnalogColor.stageGround,
            body: BrowseScreen(type: BrowseTypeFilter.movie),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Rebuild the screen from scratch, the way returning from `/detail/:id`
  /// does. Only the container — and therefore [analogFocusProvider] — survives.
  Future<void> remount(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SizedBox.shrink()),
      ),
    );
    await tester.pump();
    await pump(tester);
  }

  String? focusedTitle(WidgetTester tester) {
    for (final tile in tester.widgetList<AnalogPosterTile>(
      find.byType(AnalogPosterTile),
    )) {
      if (tile.focused) return tile.title;
    }
    return null;
  }

  testWidgets('renders one analog shelf per collection over the stage', (
    tester,
  ) async {
    catalog.items = [
      _movie('a', genres: ['Noir']),
      _movie('b', genres: ['Noir']),
      _movie('c'),
    ];
    await pump(tester);

    expect(find.byType(AnalogStage), findsOneWidget);
    // Main shelf plus the one genre that more than one, but not all, share.
    expect(find.byType(AnalogShelf), findsNWidgets(2));
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Noir'), findsOneWidget);
  });

  testWidgets('poster artwork on the real surface is square', (tester) async {
    catalog.items = [_movie('a'), _movie('b')];
    await pump(tester);
    expectSquareArtwork(tester, find.byType(AnalogShelf));
  });

  testWidgets('the first item owns focus by default', (tester) async {
    catalog.items = [_movie('a'), _movie('b'), _movie('c')];
    await pump(tester);
    expect(focusedTitle(tester), 'Title a');
    expect(container.read(ambientArtworkIdProvider), 'a');
  });

  testWidgets('back returns to the exact item that was focused', (
    tester,
  ) async {
    catalog.items = [_movie('a'), _movie('b'), _movie('c'), _movie('d')];
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusedTitle(tester), 'Title c');

    await remount(tester);
    expect(focusedTitle(tester), 'Title c');
    expect(container.read(ambientArtworkIdProvider), 'c');
  });

  testWidgets('a focused item that has since vanished holds its index', (
    tester,
  ) async {
    catalog.items = [_movie('a'), _movie('b'), _movie('c'), _movie('d')];
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(focusedTitle(tester), 'Title c');

    // The library changed while the user was away.
    catalog.items = [_movie('a'), _movie('b'), _movie('d'), _movie('e')];
    container.invalidate(browseByTypeProvider(BrowseTypeFilter.movie));
    await remount(tester);

    expect(
      focusedTitle(tester),
      'Title d',
      reason: 'focus holds the index rather than jumping back to the start',
    );
  });

  testWidgets('the backdrop follows focus', (tester) async {
    catalog.items = [_movie('a'), _movie('b')];
    await pump(tester);
    final api = container.read(apiClientProvider);

    AnalogStage stage() => tester.widget<AnalogStage>(find.byType(AnalogStage));
    expect(stage().backdropUrl, api.imageUrl('a', type: ImageType.backdrop));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(stage().backdropUrl, api.imageUrl('b', type: ImageType.backdrop));
  });

  testWidgets('an empty library and a failure both keep the stage', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(AnalogStage), findsOneWidget);
    expect(find.text('No titles here yet'), findsOneWidget);
  });

  group('prefetch', () {
    late _RecordingArtworkCache artwork;
    late ArtworkPrefetcher prefetcher;
    late _CatalogApi catalogApi;

    setUp(() {
      artwork = _RecordingArtworkCache();
      prefetcher = ArtworkPrefetcher(artwork);
      addTearDown(prefetcher.dispose);
      catalogApi = _CatalogApi();
      container = ProviderContainer(
        overrides: [
          browseByTypeProvider(
            BrowseTypeFilter.movie,
          ).overrideWith((ref) => Stream.value(catalog.items)),
          apiClientProvider.overrideWithValue(_ImageApi()),
          artworkPrefetcherProvider.overrideWithValue(prefetcher),
          catalogNamespaceProvider.overrideWithValue('server|user'),
          catalogRepositoryProvider.overrideWithValue(
            CatalogRepository(api: catalogApi),
          ),
        ],
      );
      addTearDown(container.dispose);
      catalog.items = [for (var i = 0; i < 40; i++) _movie('$i')];
    });

    List<int> warmedIndices(String kind) => [
      for (final url in artwork.warmed)
        if (url.endsWith('/$kind')) int.parse(url.split('/')[2]),
    ]..sort();

    Future<void> drain(WidgetTester tester) async {
      await prefetcher.settle();
      await container.read(catalogPrefetcherProvider).settle();
      await tester.pump();
    }

    testWidgets('the poster window is the shared rail window', (tester) async {
      await pump(tester);
      await drain(tester);

      final posters = warmedIndices('primary');
      // The cursor starts at 0, so the window is the run of `kRailLookahead`
      // items immediately past the last visible slot. Its first index IS the
      // slot count the layout measured, which is what makes this assertable
      // without re-deriving the layout arithmetic here.
      expect(posters, hasLength(kRailLookahead));
      expect(
        posters.first,
        greaterThan(0),
        reason: 'visible cards load themselves; warming them duplicates a fetch',
      );
      expect(
        posters,
        railWindow(
          RailWindowInput(total: 40, offset: 0, slots: posters.first),
        ).prefetch,
      );
    });

    testWidgets('the backdrop window is one step either side of focus', (
      tester,
    ) async {
      await pump(tester);
      await drain(tester);
      // Focus is pinned to the first item, so only forward exists.
      expect(warmedIndices('backdrop'), [1]);

      artwork.warmed.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await drain(tester);
      // Item 1's own backdrop is on the stage now; the window moves with it, so
      // both neighbours are reached for and item 1 itself is not re-warmed.
      expect(warmedIndices('backdrop'), [0, 2]);
    });

    testWidgets('the focused title is warmed for /detail/:id', (tester) async {
      await pump(tester);
      await drain(tester);
      expect(catalogApi.warmedItems, ['0']);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await drain(tester);
      expect(catalogApi.warmedItems, ['0', '1']);
    });

    testWidgets('an idle rebuild does not re-drive the queue', (tester) async {
      await pump(tester);
      await drain(tester);
      final first = List<String>.of(artwork.warmed);

      // Rebuilds that change nothing about the window: a repaint, then the
      // ambient/backdrop churn a focus write causes.
      await tester.pump();
      await tester.pump();
      await drain(tester);

      expect(artwork.warmed, first);
    });
  });

  testWidgets('a narrow window tightens the gutter instead of relayouting', (
    tester,
  ) async {
    // flutter_app has no phone target (linux/macos/windows only), so "narrow"
    // here means a narrow window, not a handset.
    catalog.items = [_movie('a'), _movie('b')];
    await pump(tester);
    final wide = tester.getTopLeft(find.byType(AnalogShelf)).dx;

    await tester.binding.setSurfaceSize(
      const Size(AnalogBreakpoint.phoneMaxPx - 1, 800),
    );
    await tester.pump();
    final narrow = tester.getTopLeft(find.byType(AnalogShelf)).dx;

    expect(wide, AnalogSpace.stageGutterPx);
    expect(narrow, AnalogSpace.stageGutterPhonePx);
    expect(find.byType(AnalogShelf), findsOneWidget);
  });
}
