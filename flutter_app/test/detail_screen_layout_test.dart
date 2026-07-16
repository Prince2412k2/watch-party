import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:watchparty/app/screens/detail_screen.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

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
          apiClientProvider.overrideWithValue(MockApiClient()),
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
}
