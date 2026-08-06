import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:watchparty/app/screens/party_screen.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/livekit/livekit_room.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

/// The party surface's top-left control is a MINIMIZE, and used to be anything
/// but: a host's press emitted `party:backToLobby` (stopping the movie for the
/// whole room) and a guest's left the party outright, tearing down its own
/// socket — both behind a plain back arrow, and neither undoable (audit #61).
class _NoopLiveKitRoomService extends LiveKitRoomService {
  @override
  Future<void> connect(
    String url,
    String token, {
    bool enableMic = true,
    bool enableCamera = true,
  }) async {}

  @override
  Future<void> disconnect() async {}
}

Widget _shadcn(BuildContext context, Widget? child) => sc.ShadcnLayer(
  theme: AppShadcnTheme.dark,
  themeMode: sc.ThemeMode.dark,
  child: child!,
);

void main() {
  Future<(ProviderContainer, MockSocketClient, GoRouter)> pumpParty(
    WidgetTester tester, {
    required String myUserId,
    required String hostId,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final socket = MockSocketClient();
    await socket.connect();
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(MockApiClient()),
        socketClientProvider.overrideWithValue(socket),
        playerControllerProvider.overrideWithValue(MockPlayerController()),
        livekitRoomServiceProvider.overrideWithValue(_NoopLiveKitRoomService()),
        currentUserIdProvider.overrideWithValue(myUserId),
      ],
    );
    addTearDown(container.dispose);
    container.read(partyProvider.notifier).setState(
      PartyState(
        id: 'ROOM1234',
        hostId: hostId,
        participants: [
          Participant(userId: hostId, name: 'Host', isHost: true),
          if (hostId != myUserId) Participant(userId: myUserId, name: 'Me'),
        ],
      ),
    );

    final router = GoRouter(
      initialLocation: '/party/ROOM1234',
      routes: [
        GoRoute(
          path: '/party/:id',
          builder: (_, state) => PartyScreen(partyId: state.pathParameters['id']),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('Shell')),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.dark,
          builder: _shadcn,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (container, socket, router);
  }

  testWidgets('a host minimizing keeps the room watching, and latches the '
      'shell out of re-opening it', (tester) async {
    final (container, socket, _) = await pumpParty(
      tester,
      myUserId: 'host1',
      hostId: 'host1',
    );

    await tester.tap(find.byKey(const Key('minimizePartyButton')));
    await tester.pumpAndSettle();

    expect(find.text('Shell'), findsOneWidget);
    // No `party:backToLobby`: minimizing must not stop the movie for the room.
    expect(socket.emitted, isEmpty);
    expect(socket.isConnected, isTrue);
    expect(container.read(partyProvider), isNotNull);
    expect(container.read(partyMinimizedProvider), 'ROOM1234');
  });

  testWidgets('a guest minimizing stays in the party', (tester) async {
    final (container, socket, _) = await pumpParty(
      tester,
      myUserId: 'guest1',
      hostId: 'host1',
    );

    await tester.tap(find.byKey(const Key('minimizePartyButton')));
    await tester.pumpAndSettle();

    expect(find.text('Shell'), findsOneWidget);
    // The guest's Back used to be a full leave — socket, A/V and sync torn down.
    expect(socket.isConnected, isTrue);
    expect(container.read(partyProvider), isNotNull);
    expect(container.read(partyMinimizedProvider), 'ROOM1234');
  });

  testWidgets('returning to the party surface clears the latch', (tester) async {
    final (container, _, router) = await pumpParty(
      tester,
      myUserId: 'guest1',
      hostId: 'host1',
    );
    await tester.tap(find.byKey(const Key('minimizePartyButton')));
    await tester.pumpAndSettle();
    expect(container.read(partyMinimizedProvider), 'ROOM1234');

    // What the popcorn's "Return to the party" does.
    router.go('/party/ROOM1234');
    await tester.pumpAndSettle();

    expect(container.read(partyMinimizedProvider), isNull);
    expect(find.text('In the lobby'), findsOneWidget);
  });
}
