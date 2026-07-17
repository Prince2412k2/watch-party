import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/theme.dart';
import 'package:watchparty/ui/widgets/bottom_nav.dart';
import 'package:watchparty/ui/widgets/nav_rail.dart';

void main() {
  testWidgets('inactive destinations remain pointer-hit-testable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(
            child: BottomNav(
              destinations: const [
                NavDestination(
                  icon: Icons.movie_outlined,
                  label: 'Movies',
                  route: '/movies',
                ),
                NavDestination(
                  icon: Icons.tv_outlined,
                  label: 'TV',
                  route: '/tv',
                ),
              ],
              currentRoute: '/movies',
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('TV')));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
