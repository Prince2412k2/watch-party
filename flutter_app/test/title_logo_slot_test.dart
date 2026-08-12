import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/screens/title_layout.dart';
import 'package:watchparty/ui/widgets/title_logo.dart';

/// Mirrors the detail page's heading slot: the fixed box the mark lands in,
/// with the Hero as the box itself and nothing loose in between.
Widget _slot(String? url) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GENRES'),
          SizedBox(
            width: TitleLayout.logoBoxWidth,
            height: TitleLayout.logoDetailHeight,
            child: Hero(
              tag: 'logo-x',
              child: TitleLogo(
                url: url,
                maxHeightPx: TitleLayout.logoDetailHeight,
                child: const Text('Fallback title'),
              ),
            ),
          ),
          const Text('SYNOPSIS'),
        ],
      ),
    ),
  ),
);

void main() {
  // An unreachable URL stands in for "the bytes have not arrived yet", which
  // is what every FIRST open of a title looks like.
  const absent = 'https://example.invalid/logo.png';

  testWidgets('the heading slot is the same height loaded or not', (
    tester,
  ) async {
    await tester.pumpWidget(_slot(absent));
    await tester.pump();
    final gap =
        tester.getRect(find.text('SYNOPSIS')).top -
        tester.getRect(find.text('GENRES')).bottom;
    expect(
      gap,
      TitleLayout.logoDetailHeight,
      reason: 'the slot must hold its room before the artwork lands',
    );
  });

  testWidgets('the flying box is the same rect whatever is inside it', (
    tester,
  ) async {
    await tester.pumpWidget(_slot(absent));
    await tester.pump();

    // A hero interpolates its BOX. Sizing that box to its contents is what
    // made the mark dive and spring back: mid-flight the contents are a line
    // of text standing in for artwork that has not downloaded, so the mark
    // flew into the rect of a line of type.
    expect(
      tester.getSize(find.byType(Hero)),
      const Size(TitleLayout.logoBoxWidth, TitleLayout.logoDetailHeight),
      reason: 'the box must not follow whatever happens to be rendered in it',
    );
  });

  testWidgets('the aside end is a fixed box too', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: AsideTitleLogo(
                itemId: 'x',
                url: absent,
                maxHeightPx: TitleLayout.asideLogoHeight,
                widthPx: TitleLayout.logoBoxWidth,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    // Both ends definite means the flight is one rect into another, rather
    // than into whichever of them has finished loading.
    expect(
      tester.getSize(find.byType(AsideTitleLogo)),
      const Size(TitleLayout.logoBoxWidth, TitleLayout.asideLogoHeight),
    );
  });
}
