import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/screens/profile_screen.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/profile.dart';
import 'package:watchparty/state/providers.dart';
import 'package:watchparty/ui/theme.dart';

class _ProfileApi extends MockApiClient {
  @override
  Future<AvatarOptions> avatarOptions() async => const AvatarOptions(
    groups: [
      AvatarGroup(
        id: 'head',
        label: 'Hair',
        slots: [
          AvatarSlot(
            id: 'head',
            label: 'Hair',
            parts: [
              AvatarPart(id: 'short', name: 'short'),
              AvatarPart(id: 'long', name: 'long'),
            ],
          ),
        ],
      ),
      AvatarGroup(
        id: 'body',
        label: 'Top',
        slots: [
          AvatarSlot(
            id: 'body',
            label: 'Top',
            parts: [AvatarPart(id: 'tee', name: 'tee')],
          ),
        ],
      ),
      AvatarGroup(
        id: 'bottom',
        label: 'Bottom',
        slots: [
          AvatarSlot(
            id: 'bottom',
            label: 'Bottom',
            parts: [AvatarPart(id: 'shorts', name: 'shorts')],
          ),
        ],
      ),
    ],
    colors: [
      AvatarColorSlot(
        id: 'hair',
        label: 'Hair',
        defaultHex: '1B1512',
        allowTransparent: false,
      ),
      AvatarColorSlot(
        id: 'clothes',
        label: 'Clothes',
        defaultHex: 'ECEAE5',
        allowTransparent: false,
      ),
      AvatarColorSlot(
        id: 'bottom',
        label: 'Bottom',
        defaultHex: '2B2F36',
        allowTransparent: false,
      ),
    ],
    palettes: {
      'hair': ['1B1512', '6B4A2F'],
      'clothes': ['ECEAE5', '7C8A5C'],
      'bottom': ['2B2F36', '6B5A48'],
    },
    defaultBackground: 'F6F5F4',
  );
}

void main() {
  test('row depth falls by a third over two steps and then holds', () {
    expect(profileRowScaleAt(0), 1);
    expect(profileRowScaleAt(1), closeTo(0.835, 0.0001));
    expect(profileRowScaleAt(2), closeTo(0.67, 0.0001));
    expect(profileRowScaleAt(5), closeTo(0.67, 0.0001));
    expect(profileRowOpacityAt(0), 1);
    expect(profileRowOpacityAt(1), 0.68);
    expect(profileRowOpacityAt(2), 0.44);
    expect(profileRowOpacityAt(5), 0.44);
  });

  test('the circular rail exposes only the center and two rows per side', () {
    final distances = [
      for (var index = 0; index < 6; index++)
        profileCircularDistance(index, 0, 6),
    ];

    expect(distances.where((distance) => distance.abs() <= 2).length, 5);
    expect(profileCircularDistance(0, 5, 6), 1);
    expect(profileCircularDistance(5, 0, 6), -1);
  });

  testWidgets('places the avatar beside the editor on a wide window', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_ProfileApi())],
        child: MaterialApp(theme: AppTheme.dark, home: const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final avatar = find.byKey(const ValueKey('profile-avatar-stage'));
    final editor = find.byKey(const ValueKey('profile-editor-panel'));

    expect(avatar, findsOneWidget);
    expect(tester.getSize(avatar), const Size.square(300));
    expect(tester.getCenter(avatar).dx, lessThan(500));
    expect(editor, findsOneWidget);
    expect(tester.getSize(editor).width, lessThanOrEqualTo(720));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the center row owns focus and its wheel opens presets', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_ProfileApi())],
        child: MaterialApp(theme: AppTheme.dark, home: const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    double scaleAt(int index) => tester
        .widget<AnimatedScale>(
          find.descendant(
            of: find.byKey(ValueKey('profile-row-$index')),
            matching: find.byType(AnimatedScale),
          ),
        )
        .scale;

    expect(scaleAt(1), 1);
    expect(scaleAt(0), closeTo(0.835, 0.0001));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scaleAt(2), 1);
    expect(scaleAt(1), closeTo(0.835, 0.0001));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(scaleAt(0), 1, reason: 'down wraps from the last row to the first');

    await tester.tap(find.byKey(const ValueKey('profile-row-1')));
    await tester.pumpAndSettle();
    expect(scaleAt(1), 1, reason: 'clicking a row brings it to the cursor');

    await tester.tap(find.byKey(const ValueKey('profile-color-wheel-clothes')));
    await tester.pumpAndSettle();

    expect(find.text('Clothes'), findsOneWidget);
    expect(find.bySemanticsLabel('Clothes #ECEAE5'), findsOneWidget);
    expect(find.bySemanticsLabel('Clothes #7C8A5C'), findsOneWidget);
  });

  testWidgets('left and right wrap choices inside the focused row', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 800));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(_ProfileApi())],
        child: MaterialApp(theme: AppTheme.dark, home: const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Short' &&
            widget.properties.selected == true,
      ),
      findsOneWidget,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Long' &&
            widget.properties.selected == true,
      ),
      findsOneWidget,
      reason: 'left wraps from the first choice to the last',
    );
  });
}
