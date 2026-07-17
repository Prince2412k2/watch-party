import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:watchparty/app/screens/app_shell.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

/// AppShell chrome renders shadcn tooltips/badges, so it needs a shadcn `Theme`
/// ancestor — mirror the app's `ShadcnLayer` wrap here.
Widget _shadcn(BuildContext context, Widget? child) => sc.ShadcnLayer(
  theme: AppShadcnTheme.dark,
  themeMode: sc.ThemeMode.dark,
  child: child!,
);

/// A bare `ProviderScope` defaults `authProvider` to its un-initialized,
/// logged-out `AuthState()`. Signed-in tests need an authenticated override to
/// exercise the full four-tab nav.
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

Widget _shell({
  required List<Override> overrides,
  String location = '/movies',
}) => MaterialApp(
  theme: AppTheme.dark,
  builder: _shadcn,
  home: ProviderScope(
    overrides: overrides,
    child: AppShell(location: location, child: const SizedBox()),
  ),
);

void main() {
  testWidgets('AppShell shows the four web nav tabs when signed in', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(_shell(overrides: _signedIn()));
    await tester.pump();

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Shows'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('AppShell shows the guest tabs + login when logged out', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await tester.pumpWidget(_shell(overrides: const []));
    await tester.pump();

    // Guest nav is just browse + downloaded; no Shows/Discover tabs.
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Downloaded'), findsOneWidget);
    expect(find.text('Shows'), findsNothing);
    expect(find.text('Discover'), findsNothing);
    // Top-right chrome is the login control, not the profile avatar.
    expect(find.byIcon(Icons.login), findsOneWidget);
  });

  group('shellSectionTitle', () {
    test('maps shelled locations (incl. nested paths) to their section', () {
      expect(shellSectionTitle('/movies'), 'Movies');
      expect(shellSectionTitle('/series'), 'Shows');
      expect(shellSectionTitle('/discover'), 'Discover');
      expect(shellSectionTitle('/discover/abc123'), 'Discover');
      expect(shellSectionTitle('/downloads'), 'Downloads');
    });

    test('falls back to the app name off the shell', () {
      expect(shellSectionTitle('/login'), 'Watchparty');
      expect(shellSectionTitle('/detail/xyz'), 'Watchparty');
      expect(shellSectionTitle('/'), 'Watchparty');
    });
  });
}
