import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/ui.dart';

void main() {
  testWidgets('arrow keys move and activate the selected poster', (
    tester,
  ) async {
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
            itemBuilder: (_, index) =>
                SizedBox(width: 190, child: Text('Poster $index')),
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

  testWidgets('hover selects a poster without playing movement sound', (
    tester,
  ) async {
    var selected = 0;
    var sounds = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PosterShelf(
            title: 'Movies',
            itemCount: 3,
            onSelectionChanged: (index) => selected = index,
            onMovementSound: () => sounds++,
            itemBuilder: (_, index) =>
                SizedBox(width: 190, height: 320, child: Text('Poster $index')),
          ),
        ),
      ),
    );
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('poster-shelf-item-1'))),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(selected, 1);
    expect(sounds, 0);
  });

  testWidgets('clips offscreen posters to the shelf viewport', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PosterShelf(
            title: 'Movies',
            itemCount: 2,
            itemBuilder: (_, index) =>
                SizedBox(width: 190, child: Text('Poster $index')),
          ),
        ),
      ),
    );

    final list = tester.widget<ListView>(find.byType(ListView));
    expect(list.clipBehavior, Clip.hardEdge);
  });

  testWidgets('can center a shelf inside the available viewport height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const SizedBox(
          width: 900,
          height: 700,
          child: PosterShelf(
            title: 'Movies',
            fillAvailableHeight: true,
            itemCount: 1,
            itemBuilder: _testPoster,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(PosterShelf)).height, 600);
    final posterCenter = tester.getCenter(find.text('Poster 0')).dy;
    expect(posterCenter, inInclusiveRange(250, 500));
  });
}

Widget _testPoster(BuildContext context, int index) =>
    SizedBox(width: 190, height: 320, child: Text('Poster $index'));
