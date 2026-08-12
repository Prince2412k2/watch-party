import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/screens/profile_screen.dart';
import 'package:watchparty/app/screens/settings_screen.dart';
import 'package:watchparty/ui/ui.dart';

/// The face is a shared element between these two: the pencil on settings
/// opens the editor, and the artwork flies rather than cuts. A flight that
/// ends somewhere other than where it started reads as a mistake, so the two
/// pages have to put the face in exactly the same rectangle.
void main() {
  Future<Rect> faceIn(WidgetTester tester, Widget screen, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp(theme: AppTheme.dark, home: screen)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return tester.getRect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == profileAvatarHeroTag,
      ),
    );
  }

  for (final size in const [Size(1400, 900), Size(1920, 1080)]) {
    testWidgets('the face lands in the same place at ${size.width.toInt()}w', (
      tester,
    ) async {
      final settings = await faceIn(tester, const SettingsScreen(), size);
      final editor = await faceIn(tester, const ProfileScreen(), size);
      expect(
        settings,
        editor,
        reason: 'settings and the editor must agree on where the face is',
      );
    });
  }
}
