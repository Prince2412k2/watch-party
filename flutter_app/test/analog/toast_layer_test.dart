import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/chrome.dart';

/// The rail has to outrank everything the app can put on screen, because the
/// things most worth announcing — someone joining, a message, a reconnect
/// failing — happen while a dialog or the watch-party control panel is open.
/// Mounting the host inside the router would put it UNDER those, and nothing
/// about the code would look wrong.
void main() {
  Widget app({required Widget Function(BuildContext) home, double inset = 0}) =>
      MaterialApp(
        builder: (context, child) => AnalogToastHost(
          topInsetPx: inset,
          child: Material(
            type: MaterialType.transparency,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: Builder(builder: home),
      );

  testWidgets('a notice raised over a dialog still renders', (tester) async {
    late BuildContext rootContext;
    await tester.pumpWidget(
      app(
        home: (context) {
          rootContext = context;
          return const SizedBox.expand();
        },
      ),
    );

    // A modal route on top of everything the router owns.
    unawaitedShowDialog(rootContext);
    await tester.pumpAndSettle();
    expect(find.text('a dialog'), findsOneWidget);

    showAnalogToast(rootContext, 'someone joined');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Both on screen: the notice is not covered by the modal, and the modal is
    // not dismissed by the notice.
    expect(find.text('someone joined'), findsOneWidget);
    expect(find.text('a dialog'), findsOneWidget);
  });

  testWidgets('the rail clears the desktop caption strip', (tester) async {
    late BuildContext rootContext;
    await tester.pumpWidget(
      app(
        inset: 32,
        home: (context) {
          rootContext = context;
          return const SizedBox.expand();
        },
      ),
    );

    showAnalogToast(rootContext, 'clear of the caption');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final top = tester.getTopLeft(find.text('clear of the caption')).dy;
    // Below the 32px strip the window chrome draws over, rather than under it.
    expect(top, greaterThan(32));
  });
}

void unawaitedShowDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const Dialog(child: Text('a dialog')),
  );
}
