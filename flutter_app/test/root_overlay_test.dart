import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/app/app.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/player/player_view.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

/// Root-mounted chrome must have an Overlay above it.
///
/// `MaterialApp.builder` wraps the Navigator rather than living inside it, so
/// nothing mounted there inherits the Navigator's Overlay — and Tooltip,
/// dialogs, menus and text selection all require one. The player's transport
/// bar is full of tooltips, so the first frame of a film threw
/// "No Overlay widget found" and kept throwing on every rebuild after.
///
/// The earlier tests missed this because they exercised each piece in
/// isolation, under a plain MaterialApp `home:` — which DOES supply an Overlay.
/// Only the real app's builder is missing one, so only a test that boots the
/// real app can catch it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> bootApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConfigProvider.overrideWith(
            (ref) => ServerConfigNotifier(ref, 'http://mock.local'),
          ),
          playerControllerProvider.overrideWithValue(MockPlayerController()),
          authProvider.overrideWith((ref) {
            final notifier = AuthNotifier(ref);
            notifier.state = const AuthState(
              user: User(userId: 'u1', name: 'Test User'),
              initialized: true,
            );
            return notifier;
          }),
        ],
        child: const WatchpartyApp(enableWindowFrame: false),
      ),
    );
    await tester.pumpAndSettle();
  }

  _popcornOverFilmTests();

  testWidgets('the player mounts over the app without an Overlay error', (
    tester,
  ) async {
    await bootApp(tester);

    // `fromParty: true` so the host renders the player straight away instead of
    // running the real open pipeline (and its never-settling spinner). The
    // chrome — and its tooltips — build either way, which is the point.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WatchpartyApp)),
    );
    container
        .read(nowPlayingProvider.notifier)
        .open(itemId: 'movie-1', title: 'Arrival', fromParty: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PlayerView), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'root-mounted chrome needs an Overlay ancestor',
    );
  });

  testWidgets('the popcorn builds its tooltips at the root too', (
    tester,
  ) async {
    // The popcorn used to carry a private Overlay of its own. That papered over
    // the symptom for the one widget I had tested and left the player to fail
    // at runtime, so the fix moved up to a single Overlay around all of it —
    // and this asserts the popcorn still works from there.
    await bootApp(tester);
    // The tray's buttons are built even while it is rolled up, so this is not
    // a before/after assertion — it is "the tooltip widget can build at all".
    await tester.tap(find.byType(PopcornControl));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Start a watch party'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The popcorn over a film.
///
/// Mounting it at the root put it above the player — right for reachability
/// (you can end a party without leaving the film) and wrong for everything
/// else: it sat on top of the transport bar's volume and settings controls, and
/// it was the one thing still lit when the rest of the chrome faded away.
void _popcornOverFilmTests() {
  testWidgets('over a film the popcorn lifts clear and fades with the chrome', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConfigProvider.overrideWith(
            (ref) => ServerConfigNotifier(ref, 'http://mock.local'),
          ),
          playerControllerProvider.overrideWithValue(MockPlayerController()),
          authProvider.overrideWith((ref) {
            final notifier = AuthNotifier(ref);
            notifier.state = const AuthState(
              user: User(userId: 'u1', name: 'Test User'),
              initialized: true,
            );
            return notifier;
          }),
        ],
        child: const WatchpartyApp(enableWindowFrame: false),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(WatchpartyApp)),
    );
    final restingBottom =
        900 - tester.getBottomLeft(find.byType(PopcornControl)).dy;

    container
        .read(nowPlayingProvider.notifier)
        .open(itemId: 'movie-1', fromParty: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final overFilmBottom =
        900 - tester.getBottomLeft(find.byType(PopcornControl)).dy;
    expect(
      overFilmBottom,
      greaterThan(restingBottom),
      reason: 'it must clear the transport bar, not sit on it',
    );

    // Chrome goes idle: the popcorn goes with it rather than staying lit on an
    // otherwise cleared picture.
    container.read(playerChromeVisibleProvider.notifier).state = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final faded = tester.widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byType(PopcornControl),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    );
    expect(faded.opacity, 0);
  });
}
