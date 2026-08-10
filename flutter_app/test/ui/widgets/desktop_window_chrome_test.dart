// The window chrome wraps the whole app, the player included, so the one thing
// worth pinning about it is that its tree shape never moves. It used to return
// the bare child when fullscreen and a Stack otherwise, which remounted
// everything below it — on macOS that made Cmd+F bounce straight back out of
// fullscreen and restart the film, because PlayerHost was torn down and rebuilt.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/widgets/desktop_window_chrome.dart';
import 'package:window_manager/window_manager.dart';

/// Counts how many times it has been mounted. A remount is the bug.
class _Mounts extends StatefulWidget {
  const _Mounts();

  static int count = 0;

  @override
  State<_Mounts> createState() => _MountsState();
}

class _MountsState extends State<_Mounts> {
  @override
  void initState() {
    super.initState();
    _Mounts.count++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  setUp(() => _Mounts.count = 0);

  Future<void> pump(WidgetTester tester, {required bool fullscreen}) =>
      tester.pumpWidget(
        MaterialApp(
          home: DesktopWindowChrome(
            debugIsMacOS: true,
            debugFullscreen: fullscreen,
            child: const _Mounts(),
          ),
        ),
      );

  testWidgets('going fullscreen does not remount the app below it', (
    tester,
  ) async {
    await pump(tester, fullscreen: false);
    expect(_Mounts.count, 1);
    expect(find.byType(DragToMoveArea), findsOneWidget);

    await pump(tester, fullscreen: true);

    // The caption strip goes, and nothing else does.
    expect(find.byType(DragToMoveArea), findsNothing);
    expect(
      _Mounts.count,
      1,
      reason:
          'the child was rebuilt into a different shape and remounted — '
          'which is what tore down the player and restarted the film',
    );

    // And back out again, still the same element.
    await pump(tester, fullscreen: false);
    expect(find.byType(DragToMoveArea), findsOneWidget);
    expect(_Mounts.count, 1);
  });

  testWidgets('off macOS there is no caption strip, and still one child', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopWindowChrome(
          debugIsMacOS: false,
          debugFullscreen: false,
          child: _Mounts(),
        ),
      ),
    );

    expect(find.byType(DragToMoveArea), findsNothing);
    expect(_Mounts.count, 1);
    // The app still fills the window rather than shrink-wrapping inside the
    // stack that now always wraps it.
    expect(
      tester.getSize(find.byType(_Mounts)),
      tester.getSize(find.byType(DesktopWindowChrome)),
    );
  });
}
