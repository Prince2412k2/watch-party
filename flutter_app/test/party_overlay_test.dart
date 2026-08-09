import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/livekit/livekit_room.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/party/party_overlay.dart';
import 'package:watchparty/player/mock_player_controller.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';
import 'package:watchparty/ui/widgets/floating_camera_tile.dart';

/// The room's chrome is mounted above the router, so it has to be inert when
/// there is no room — this widget wraps EVERY screen in the app, including the
/// login screen of someone who has never opened a party. It also has to appear
/// without anyone navigating anywhere, which is the half that makes rooms
/// ambient rather than a destination.
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
        livekitRoomServiceProvider.overrideWithValue(_NoopLiveKitRoomService()),
        currentUserIdProvider.overrideWithValue('me'),
      ],
    );
  });
  tearDown(() => container.dispose());

  void joinRoom({String hostId = 'me', List<Participant>? waiting}) {
    container.read(partyProvider.notifier).setState(
      PartyState(
        id: 'ROOM1234',
        hostId: hostId,
        participants: [
          Participant(userId: hostId, name: 'Host', isHost: true),
          if (hostId != 'me') const Participant(userId: 'me', name: 'Me'),
        ],
      ),
    );
    if (waiting != null) {
      container.read(partyWaitingProvider.notifier).setAll(waiting);
    }
  }

  Future<void> pumpOverlay(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          // Mirrors app.dart: the overlay renders under a transparent
          // Material, which is what supplies the ink/text plumbing its chat
          // composer needs without painting a background.
          home: const Material(
            type: MaterialType.transparency,
            child: PartyOverlay(child: Center(child: Text('library'))),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('with no room it renders nothing but the app', (tester) async {
    await pumpOverlay(tester);
    expect(find.text('library'), findsOneWidget);
    expect(find.byType(FloatingCameraLayer), findsNothing);
    expect(find.byType(ChatSlideOver), findsNothing);
  });

  testWidgets('joining a room brings cameras and chat, without navigating', (
    tester,
  ) async {
    // The point of the whole task: you are still on the same screen. Nothing
    // pushed a route, and the library underneath is untouched.
    await pumpOverlay(tester);
    joinRoom();
    await tester.pump();

    expect(find.byType(FloatingCameraLayer), findsOneWidget);
    expect(find.byType(ChatSlideOver), findsOneWidget);
    expect(find.text('library'), findsOneWidget);
  });

  testWidgets('the chat drawer is parked off-screen until it is opened', (
    tester,
  ) async {
    await pumpOverlay(tester);
    joinRoom();
    await tester.pumpAndSettle();
    final closed = tester.getTopLeft(find.byType(ChatSlideOver)).dx;
    expect(closed, greaterThan(1200 - kChatDrawerWidth));

    container.read(chatDrawerOpenProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(ChatSlideOver)).dx,
      1200 - kChatDrawerWidth,
    );
  });

  testWidgets('join requests reach the host wherever they are standing', (
    tester,
  ) async {
    await pumpOverlay(tester);
    joinRoom(waiting: const [Participant(userId: 'gate', name: 'Nadia')]);
    await tester.pumpAndSettle();

    expect(find.text('Nadia'), findsOneWidget);
    expect(find.text('wants to join'), findsOneWidget);
  });

  testWidgets('a guest is never shown the join queue', (tester) async {
    await pumpOverlay(tester);
    joinRoom(
      hostId: 'someone-else',
      waiting: const [Participant(userId: 'gate', name: 'Nadia')],
    );
    await tester.pumpAndSettle();

    expect(find.text('Nadia'), findsNothing);
  });
}
