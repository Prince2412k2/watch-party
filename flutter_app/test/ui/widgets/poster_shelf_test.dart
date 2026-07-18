import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/ui.dart';

void main() {
  testWidgets('arrow keys move and activate the selected poster', (tester) async {
    var selected = 0;
    var activated = -1;
    var sounds = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PosterShelf(
            title: 'Movies',
            itemCount: 3,
            autofocus: true,
            onSelectionChanged: (index) => selected = index,
            onActivate: (index) => activated = index,
            onMovementSound: () => sounds++,
            itemBuilder: (_, index) => SizedBox(
              width: 190,
              child: Text('Poster $index'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 300));
    expect(selected, 1);
    expect(sounds, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 300));
    expect(selected, 0);
    expect(sounds, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(selected, 0);
    expect(sounds, 2);
  });
}
