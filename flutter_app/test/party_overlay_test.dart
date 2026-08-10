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
    container
        .read(partyProvider.notifier)
        .setState(
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
            child: Stack(
              children: [
                Positioned.fill(child: Center(child: Text('library'))),
                Positioned.fill(child: PartyOverlay()),
              ],
            ),
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
    // Present in the tree is not the same as visible. The overlay's own Stack
    // holds only positioned children, so under loose constraints it shrinks to
    // nothing and every tile inside it collapses while still being findable —
    // which is exactly how the cameras and the device rail disappeared once
    // this stopped wrapping the app.
    expect(
      tester.getSize(find.byType(FloatingCameraLayer)).height,
      greaterThan(0),
    );
  });

  testWidgets('device controls fade with expanded player chrome', (
    tester,
  ) async {
    joinRoom();
    container.read(nowPlayingProvider.notifier).open(itemId: 'movie-1');
    await pumpOverlay(tester);

    AnimatedOpacity rail() => tester.widget<AnimatedOpacity>(
      find.byKey(const Key('deviceRailVisibility')),
    );

    expect(rail().opacity, 1);
    container.read(playerChromeVisibleProvider.notifier).state = false;
    await tester.pump();
    expect(rail().opacity, 0);

    container.read(nowPlayingProvider.notifier).minimise();
    await tester.pump();
    expect(rail().opacity, 1);
  });

  testWidgets('the chat drawer grows out of the right edge when opened', (
    tester,
  ) async {
    // It is no longer a full-width panel parked off-screen: closed, the glass
    // does not exist at all, and opening grows it from a blob at the edge. So
    // the assertion is about WIDTH over time, not position.
    //
    // Pumped by hand rather than settled: the panel is deformed by a jelly
    // spring, which is not guaranteed to come to rest inside pumpAndSettle.
    await pumpOverlay(tester);
    joinRoom();
    await tester.pump();
    expect(find.byType(ChatPanel), findsNothing);

    container.read(chatDrawerOpenProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final early = tester.getSize(find.byType(ChatSlideOver)).width;

    await tester.pump(const Duration(milliseconds: 600));
    final settled = tester.getSize(find.byType(ChatSlideOver)).width;

    expect(early, lessThan(settled), reason: 'it stretches out, not in');
    expect(settled, closeTo(kChatDrawerWidth, 12));
    expect(find.byType(ChatPanel), findsOneWidget);
    final card = tester.widget<DecoratedBox>(
      find.byKey(const Key('chatSidebarCard')),
    );
    final decoration = card.decoration as BoxDecoration;
    expect(decoration.color?.a, 1);
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('the chat composer keeps focus after sending', (tester) async {
    await pumpOverlay(tester);
    joinRoom();
    container.read(chatDrawerOpenProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final input = find.byKey(const Key('chatInput'));
    EditableText editable() => tester.widget<EditableText>(
      find.descendant(of: input, matching: find.byType(EditableText)),
    );

    expect(editable().focusNode.hasFocus, isTrue);
    await tester.enterText(input, 'Still typing');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    expect(editable().focusNode.hasFocus, isTrue);
  });

  testWidgets('join requests reach the host wherever they are standing', (
    tester,
  ) async {
    await pumpOverlay(tester);
    joinRoom(
      waiting: const [Participant(userId: 'gate', name: 'Nadia')],
    );
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
