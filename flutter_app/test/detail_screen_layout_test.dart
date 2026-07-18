import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:watchparty/app/screens/detail_screen.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

class _ZeroRuntimeApi extends MockApiClient {
  @override
  Future<LibraryItem> item(String id) async {
    final item = await super.item(id);
    return item.copyWith(runTimeTicks: 0);
  }
}

class _SeriesApi extends MockApiClient {
  static const series = LibraryItem(
    id: 'series',
    name: 'Signal',
    type: 'Series',
    overview:
        'A deliberately long series synopsis that exercises the bounded '
        'desktop copy layout while the episode dock remains visible below it. '
        'The copy keeps going so a short window must scroll rather than overflow.',
    genres: ['Drama', 'Mystery'],
  );
  static const season = LibraryItem(
    id: 'season-1',
    name: 'Season 1',
    type: 'Season',
    indexNumber: 1,
  );
  static const first = LibraryItem(
    id: 'episode-1',
    name: 'First Contact',
    type: 'Episode',
    seriesId: 'series',
    seriesName: 'Signal',
    parentId: 'season-1',
    parentIndexNumber: 1,
    indexNumber: 1,
    runTimeTicks: 30000000000,
  );
  static const second = LibraryItem(
    id: 'episode-2',
    name: 'The Extremely Long Second Episode Name',
    type: 'Episode',
    seriesId: 'series',
    seriesName: 'Signal',
    parentId: 'season-1',
    parentIndexNumber: 1,
    indexNumber: 2,
    runTimeTicks: 30000000000,
  );

  final secondDetail = Completer<LibraryItem>();

  @override
  Future<LibraryItem> item(String id) {
    if (id == second.id) return secondDetail.future;
    return Future.value(switch (id) {
      'episode-1' => first,
      _ => series,
    });
  }

  @override
  Future<List<LibraryItem>> children(String itemId) async => switch (itemId) {
    'series' => [season],
    'season-1' => [first, second],
    _ => const [],
  };
}

void main() {
  testWidgets('detail screen lays out without unbounded-constraint errors', (
    tester,
  ) async {
    final errors = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());

    final semantics = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      ProviderScope(
        // A bare `authProvider` defaults to logged-out, which now renders the
        // guest offline-only branch instead of the server-backed hero this
        // test exercises — sign in so the real layout is what's under test.
        overrides: [
          apiClientProvider.overrideWithValue(_ZeroRuntimeApi()),
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
          builder: (context, child) => sc.ShadcnLayer(
            theme: AppShadcnTheme.dark,
            themeMode: sc.ThemeMode.dark,
            child: child!,
          ),
          home: const DetailScreen(itemId: 'mock-item-0'),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // Nudge relayout so semantics recompile (parentDataDirty fired here before).
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    FlutterError.onError = prev;
    semantics.dispose();

    expect(
      errors,
      isEmpty,
      reason: 'layout/semantics errors: ${errors.take(2)}',
    );
  });

  testWidgets('episode selection keeps show details visible while loading', (
    tester,
  ) async {
    final errors = <String>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details.exceptionAsString());
    addTearDown(() => FlutterError.onError = previousOnError);

    final api = _SeriesApi();
    await tester.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
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
          builder: (context, child) => sc.ShadcnLayer(
            theme: AppShadcnTheme.dark,
            themeMode: sc.ThemeMode.dark,
            child: child!,
          ),
          home: const DetailScreen(itemId: 'series'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(_SeriesApi.second.name));
    await tester.pump();

    expect(find.text('Signal'), findsOneWidget);
    expect(find.textContaining('S1 E2'), findsOneWidget);
    expect(api.secondDetail.isCompleted, isFalse);
    expect(errors, isEmpty, reason: 'layout errors: ${errors.take(2)}');

    api.secondDetail.complete(_SeriesApi.second);
    await tester.pumpAndSettle();
  });
}
