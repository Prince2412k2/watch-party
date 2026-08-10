import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/artwork_cache.dart';
import 'package:watchparty/state/providers.dart';
import 'package:watchparty/ui/widgets/title_logo.dart';

/// A 400×100 red PNG — a stand-in for logo artwork, wide the way real logos are.
final _logoBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAZAAAABkCAYAAACoy2Z3AAABfUlEQVR4nO3VsQ0AIAzAsP7/dLmBLA'
  'jJg/dsmZ1ZALg1rwMA+JOBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQCQGAgAiYEAkBgIAI'
  'mBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQCQGAgAiY'
  'EAkBgIAImBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQ'
  'CQGAgAiYEAkBgIAImBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQCQGAgAiYEAkBgIAImBAJ'
  'AYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQCQGAgAiYEAkB'
  'gIAImBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCACJgQCQGA'
  'gAiYEAkBgIAImBAJAYCACJgQCQGAgAiYEAkBgIAImBAJAYCADJAbhmWbr3kGqOAAAAAElFTkSuQmCC',
);

/// An [ArtworkCache] that already holds the artwork, so the image resolves
/// synchronously and the widget's laid-out size is the thing under test.
class _WarmCache extends ArtworkCache {
  _WarmCache() : super(Dio(), directory: Directory.systemTemp);

  @override
  Uint8List? peek(String url) => _logoBytes;

  @override
  Stream<Uint8List> load(String url) => Stream.value(_logoBytes);
}

Widget _host(Widget child, {ArtworkCache? cache}) => ProviderScope(
  overrides: [artworkCacheProvider.overrideWithValue(cache)],
  child: MaterialApp(
    home: Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // An Expanded in a Row is how the show stage holds its heading, and a
          // tight width is exactly what a logo must not be sized from.
          Row(children: [Expanded(child: child)]),
        ],
      ),
    ),
  ),
);

void main() {
  const heading = Text('The Grand Budapest Hotel');

  testWidgets('no logo image leaves the text heading in place', (tester) async {
    await tester.pumpWidget(
      _host(const TitleLogo(url: null, maxHeightPx: 92, child: heading)),
    );

    expect(find.text('The Grand Budapest Hotel'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('artwork that cannot be fetched falls back to the text', (
    tester,
  ) async {
    // No cache installed and no network in a test: the fetch fails, which is
    // the same outcome as a Logo tag the server no longer honours.
    await tester.pumpWidget(
      _host(
        const TitleLogo(url: '/logo.png', maxHeightPx: 92, child: heading),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The Grand Budapest Hotel'), findsOneWidget);
  });

  testWidgets('the logo takes the heading\'s place, sized by the artwork', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const TitleLogo(url: '/logo.png', maxHeightPx: 92, child: heading),
        cache: _WarmCache(),
      ),
    );
    await tester.pump();

    expect(find.text('The Grand Budapest Hotel'), findsNothing);
    expect(find.byType(Image), findsOneWidget);

    // The regression this guards: these headings sit in an `Expanded`, and an
    // image handed a tight width derives its height from that width — a 400×100
    // logo in an 800px column would lay out 200px tall. It must reach the image
    // loose so the artwork's own size wins.
    //
    // The constraint is asserted rather than the laid-out size because this
    // environment has no image codec: the bytes never become a picture here,
    // but the box they are given is the same either way.
    final constraints = tester
        .renderObject<RenderBox>(find.byType(Image))
        .constraints;
    expect(constraints.hasTightWidth, isFalse);
    expect(constraints.hasBoundedHeight, isFalse);
  });
}
