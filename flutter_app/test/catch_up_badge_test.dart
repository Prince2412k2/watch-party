import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/sync/sync_engine.dart';
import 'package:watchparty/ui/ui.dart';
import 'package:watchparty/ui/widgets/catch_up_badge.dart';

/// NEVER pumpAndSettle in here. The badge's chevrons run a repeating
/// AnimationController, which by design never settles — pumpAndSettle would
/// spin until the test timed out. Same trap the persistent-chrome spinner set.
void main() {
  late StreamController<CatchUp> catchUp;
  late ProviderContainer container;

  setUp(() {
    catchUp = StreamController<CatchUp>.broadcast();
    container = ProviderContainer(
      overrides: [catchUpProvider.overrideWith((ref) => catchUp.stream)],
    );
  });
  tearDown(() {
    container.dispose();
    catchUp.close();
  });

  Future<void> pumpBadge(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(body: Center(child: CatchUpBadge())),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('says nothing while playback is running at normal speed', (
    tester,
  ) async {
    // The overwhelmingly common case. A badge that is present-but-idle would be
    // permanent furniture on the picture.
    await pumpBadge(tester);
    expect(find.text('CATCHING UP'), findsNothing);
    expect(find.text('EASING BACK'), findsNothing);
  });

  testWidgets('announces a speed-up as catching up', (tester) async {
    await pumpBadge(tester);
    catchUp.add(const CatchUp(rate: 1.1, drift: Duration(seconds: 2)));
    await tester.pump();
    await tester.pump(AppMotion.snap);

    expect(find.text('CATCHING UP'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_right), findsNWidgets(2));
  });

  testWidgets('being held back is not called catching up', (tester) async {
    // Same mechanism, opposite direction. Labelling it "catching up" would be
    // untrue, and the chevrons have to point the way playback is being pushed.
    await pumpBadge(tester);
    catchUp.add(const CatchUp(rate: 0.9, drift: Duration(seconds: -2)));
    await tester.pump();
    await tester.pump(AppMotion.snap);

    expect(find.text('EASING BACK'), findsOneWidget);
    expect(find.text('CATCHING UP'), findsNothing);
    expect(find.byIcon(Icons.keyboard_arrow_left), findsNWidgets(2));
  });

  testWidgets('float noise around 1.0 does not flicker the badge on', (
    tester,
  ) async {
    // The nudge is a float off a gain, so it lands on values like 1.0000000002
    // when the correction releases. Comparing against 1.0 exactly would flash
    // the badge every time the loop let go.
    await pumpBadge(tester);
    catchUp.add(const CatchUp(rate: 1.0000000002));
    await tester.pump();
    await tester.pump(AppMotion.snap);

    expect(find.text('CATCHING UP'), findsNothing);
  });

  testWidgets('it goes away when the correction ends', (tester) async {
    await pumpBadge(tester);
    catchUp.add(const CatchUp(rate: 1.1, drift: Duration(seconds: 2)));
    await tester.pump();
    await tester.pump(AppMotion.snap);
    expect(find.text('CATCHING UP'), findsOneWidget);

    catchUp.add(CatchUp.idle);
    await tester.pump();
    await tester.pump(AppMotion.snap);
    expect(find.text('CATCHING UP'), findsNothing);
  });
}
