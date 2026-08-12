import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/app/screens/title_layout.dart';
import 'package:watchparty/ui/widgets/title_logo.dart';

/// Mirrors the detail page's heading slot: the reserved box the logo lands in.
Widget _slot(String? url) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('GENRES'),
          SizedBox(
            height: TitleLayout.logoDetailHeight,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Hero(
                tag: 'logo-x',
                child: TitleLogo(
                  url: url,
                  maxHeightPx: TitleLayout.logoDetailHeight,
                  hugArtwork: true,
                  child: const Text('Fallback title'),
                ),
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
  testWidgets('the heading slot is the same height loaded or not', (
    tester,
  ) async {
    // An unreachable URL stands in for "the bytes have not arrived yet".
    await tester.pumpWidget(_slot('https://example.invalid/logo.png'));
    await tester.pump();
    final genre = tester.getRect(find.text('GENRES'));
    final synopsis = tester.getRect(find.text('SYNOPSIS'));
    final gap = synopsis.top - genre.bottom;

    expect(
      gap,
      TitleLayout.logoDetailHeight,
      reason: 'the slot must hold its room before the artwork lands',
    );
  });

  testWidgets('the flying box hugs the mark, not the column', (tester) async {
    await tester.pumpWidget(_slot('https://example.invalid/logo.png'));
    await tester.pump();

    // A hero interpolates its BOX. Letting this one take the column's width
    // made the two ends wildly different rectangles, so the mark scaled down
    // on the way in and sprang back at the end — the arrival everyone reads
    // as "it broke, then fixed itself".
    final hero = tester.getRect(find.byType(Hero));
    final column = tester.getRect(find.byType(Scaffold));
    expect(
      hero.width,
      lessThan(column.width),
      reason: 'the hero must not span the whole copy column',
    );
    expect(hero.width, greaterThan(0), reason: 'nor collapse to nothing');
  });

  testWidgets('the aside reserves its height too', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: AsideTitleLogo(
                itemId: 'x',
                url: 'https://example.invalid/logo.png',
                maxHeightPx: TitleLayout.asideLogoHeight,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getSize(find.byType(AsideTitleLogo)).height,
      TitleLayout.asideLogoHeight,
    );
  });
}
