import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

/// Asking to join and then being told nothing is the failure this covers.
///
/// It used to be a whole screen — the sonar waiting room on `/party/:id`. When
/// that route was deleted the state stopped being rendered anywhere: you typed
/// a code, the dialog closed, and the app looked exactly as it had before you
/// asked. Silence is the one response a request for permission must never get.
///
/// NOTE: no pumpAndSettle once pending is set. The popcorn runs a repeating
/// pulse in that state, deliberately only in that state, so it never settles.
void main() {
  late ProviderContainer container;

  setUp(() async {
    final socket = MockSocketClient();
    await socket.connect();
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(MockApiClient()),
        socketClientProvider.overrideWithValue(socket),
        playerControllerProvider.overrideWithValue(MockPlayerController()),
        currentUserIdProvider.overrideWithValue('me'),
      ],
    );
  });
  tearDown(() => container.dispose());

  Future<void> pumpPopcorn(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: PopcornControl(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('with no request outstanding the tray offers start and join', (
    tester,
  ) async {
    await pumpPopcorn(tester);
    await tester.tap(find.byType(PopcornControl));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Start a watch party'), findsOneWidget);
    expect(find.byTooltip('Join with a code'), findsOneWidget);
    expect(find.byKey(const Key('cancelJoinRequestButton')), findsNothing);
  });

  testWidgets('while waiting on the host, the tray says so and offers a way out', (
    tester,
  ) async {
    await pumpPopcorn(tester);
    container.read(partyPendingProvider.notifier).state = 'ROOM1234';
    await tester.pump();
    await tester.tap(find.byType(PopcornControl));
    // Hand-pumped past the tray animation: the pulse never settles.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('cancelJoinRequestButton')), findsOneWidget);
    // Offering these again would invite you to ask a second time while the
    // first request is still outstanding.
    expect(find.byTooltip('Start a watch party'), findsNothing);
    expect(find.byTooltip('Join with a code'), findsNothing);
  });

  testWidgets('being let in clears the waiting state', (tester) async {
    await pumpPopcorn(tester);
    container.read(partyPendingProvider.notifier).state = 'ROOM1234';
    await tester.pump();

    container.read(partyPendingProvider.notifier).state = null;
    await tester.pump();
    await tester.tap(find.byType(PopcornControl));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cancelJoinRequestButton')), findsNothing);
  });
}
