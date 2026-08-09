import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/chrome.dart';
import 'package:watchparty/net/socket_client.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/analog_tokens.dart';
import 'package:watchparty/ui/ui.dart';

/// A chat message arriving while the viewer is NOT in the player used to be
/// silent — the player owned the only toast path, so browsing the library meant
/// finding out later. These pin the notice, and the two cases that must stay
/// quiet.
void main() {
  late MockSocketClient socket;
  late ProviderContainer container;

  void build({String? me}) {
    socket = MockSocketClient();
    container = ProviderContainer(
      overrides: [
        socketClientProvider.overrideWithValue(socket),
        currentUserIdProvider.overrideWithValue(me),
      ],
    );
    // Realise the notifier so its socket subscription exists before any inject.
    container.read(chatProvider);
    addTearDown(container.dispose);
  }

  Widget harness() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: AnalogToastHost(
        child: ChatNotifications(
          child: const Material(child: SizedBox.expand()),
        ),
      ),
    ),
  );

  void inject({
    String userId = 'ada',
    String name = 'Ada',
    String text = 'popcorn is ready',
    int timestamp = 1000,
  }) {
    socket.inject('chat:message', {
      'userId': userId,
      'name': name,
      'text': text,
      'timestamp': timestamp,
    });
  }

  testWidgets('a message off the player raises a notice', (tester) async {
    build();
    await tester.pumpWidget(harness());
    inject();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Ada'), findsOneWidget);
    expect(find.textContaining('popcorn is ready'), findsOneWidget);
  });

  testWidgets('it clears on its own, without being dismissed', (tester) async {
    build();
    await tester.pumpWidget(harness());
    inject();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.textContaining('Ada'), findsOneWidget);

    await tester.pump(AnalogTiming.toastLifetimeMs);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ada'), findsNothing);
  });

  testWidgets('your own message is not announced back to you', (tester) async {
    build(me: 'me');
    await tester.pumpWidget(harness());

    inject(userId: 'me', name: 'Me', text: 'mine');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('mine'), findsNothing);
  });

  testWidgets('the backlog at mount is history, not news', (tester) async {
    build();
    // Arrived before this widget existed — joining a party mid-conversation
    // must not fire everything said so far at the viewer.
    inject(text: 'said before you got here');
    await tester.pumpWidget(harness());
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('said before you got here'), findsNothing);
  });
}
