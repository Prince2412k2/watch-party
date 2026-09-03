import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/screens/login_screen.dart';
import 'package:watchparty/app/shortcuts.dart';
import 'package:watchparty/state/state.dart';

void main() {
  testWidgets('username input preserves text and advances focus to password', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) {
            final notifier = AuthNotifier(ref);
            notifier.state = const AuthState(initialized: true);
            return notifier;
          }),
        ],
        child: const MaterialApp(home: AppShortcuts(child: LoginScreen())),
      ),
    );
    await tester.pump();

    final fields = find.byType(EditableText);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.first, 'prince.测试');
    expect(
      tester.widget<EditableText>(fields.first).controller.text,
      'prince.测试',
    );

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(
      tester.widget<EditableText>(fields.at(1)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('digit shortcuts do not consume username or password input', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) {
            final notifier = AuthNotifier(ref);
            notifier.state = const AuthState(initialized: true);
            return notifier;
          }),
        ],
        child: const MaterialApp(home: AppShortcuts(child: LoginScreen())),
      ),
    );
    await tester.pump();

    final fields = find.byType(EditableText);
    await tester.tap(fields.first);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit1), isFalse);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit2), isFalse);

    await tester.tap(fields.at(1));
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit1), isFalse);
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.digit2), isFalse);
  });
}
