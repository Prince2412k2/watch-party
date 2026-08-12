import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/screens/detail_stage.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/state.dart';
import 'package:watchparty/ui/ui.dart';

/// A title as the browse rail already knows it, logo tag included.
const _item = LibraryItem(
  id: 'film-1',
  name: 'A Seeded Title',
  type: 'Movie',
  imageTags: {'Primary': 'p', 'Logo': 'l'},
);

/// The page's own fetch, still in flight — which is what every FIRST open of a
/// title looks like. A later open resolves from cache on the first frame, and
/// that difference is the whole bug.
Widget _stage({LibraryItem? seed}) => ProviderScope(
  overrides: [
    itemDetailProvider(_item.id).overrideWith((ref) => const Stream.empty()),
  ],
  child: MaterialApp(
    theme: AppTheme.dark,
    home: DetailStage(
      itemId: _item.id,
      seed: seed,
      onWatch: (_, _) {},
      onBack: () {},
    ),
  ),
);

void main() {
  testWidgets('unseeded, there is no heading for the mark to land in', (
    tester,
  ) async {
    await tester.pumpWidget(_stage());
    await tester.pump();
    expect(
      find.byType(TitleLogo),
      findsNothing,
      reason: 'a skeleton has no heading — this is what the seed closes',
    );
  });

  testWidgets('seeded, the heading is there on the first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_stage(seed: _item));
    await tester.pump();
    expect(
      find.byType(TitleLogo),
      findsOneWidget,
      reason: 'the mark needs somewhere to land before the fetch returns',
    );
    // And it is the tagged one, so the flight actually pairs up.
    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == titleLogoHeroTag(_item.id),
      ),
      findsOneWidget,
    );
  });
}
