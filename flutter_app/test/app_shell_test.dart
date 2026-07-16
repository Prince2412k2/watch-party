import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:watchparty/app/screens/app_shell.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

/// NavRail renders a shadcn badge/tooltip, so it needs a shadcn `Theme`
/// ancestor — mirror the app's `ShadcnLayer` wrap here (assertions unchanged).
Widget _shadcn(BuildContext context, Widget? child) => sc.ShadcnLayer(
  theme: AppShadcnTheme.dark,
  themeMode: sc.ThemeMode.dark,
  child: child!,
);

/// A bare `ProviderScope` defaults `authProvider` to its un-initialized,
/// logged-out `AuthState()` — since AppShell now shows a two-tab guest rail
/// when logged out, the "authenticated" tests below need a signed-in override
/// to exercise the full rail instead.
List<Override> _signedIn() => [
  authProvider.overrideWith((ref) {
    final notifier = AuthNotifier(ref);
    notifier.state = const AuthState(
      user: User(userId: 'u1', name: 'Test User'),
      initialized: true,
    );
    return notifier;
  }),
];

void main() {
  testWidgets('AppShell shows full nav labels at desktop width', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: _shadcn,
        home: ProviderScope(
          overrides: _signedIn(),
          child: const AppShell(location: '/home', child: SizedBox()),
        ),
      ),
    );
    await tester.pump();

    // The section title now lives in the unified title bar (app.dart, above the
    // shell), so within AppShell "Home" appears once: the nav rail label.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Browse'), findsOneWidget);
  });

  testWidgets(
    'AppShell collapses to a compact icon rail below the breakpoint',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(600, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: _shadcn,
          home: ProviderScope(
            overrides: _signedIn(),
            child: const AppShell(location: '/home', child: SizedBox()),
          ),
        ),
      );
      await tester.pump();

      // Compact rail is icon-only: the "Home" label collapses to a tooltip
      // (not in the tree at rest) and the icon remains.
      expect(find.text('Home'), findsNothing);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    },
  );

  testWidgets('AppShell shows only Home + Downloaded when logged out', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: _shadcn,
        home: const ProviderScope(
          child: AppShell(location: '/home', child: SizedBox()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('Browse'), findsNothing);
    // Top-right chrome is the Login button, not the Profile avatar.
    expect(find.byIcon(Icons.login), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNothing);
  });

  group('shellSectionTitle', () {
    test('maps shelled locations (incl. nested paths) to their section', () {
      expect(shellSectionTitle('/home'), 'Home');
      expect(shellSectionTitle('/browse'), 'Browse');
      expect(shellSectionTitle('/party'), 'Party');
      expect(shellSectionTitle('/party/abc123'), 'Party');
      expect(shellSectionTitle('/downloads'), 'Downloads');
      expect(shellSectionTitle('/offline'), 'Offline');
      expect(shellSectionTitle('/servarr'), 'Find');
      expect(shellSectionTitle('/servarr/queue'), 'Find');
    });

    test('falls back to the app name off the shell', () {
      expect(shellSectionTitle('/login'), 'Watchparty');
      expect(shellSectionTitle('/detail/xyz'), 'Watchparty');
      expect(shellSectionTitle('/'), 'Watchparty');
    });
  });
}
