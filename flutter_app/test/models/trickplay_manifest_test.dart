import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/models/trickplay_manifest.dart';

void main() {
  const manifest = TrickplayManifest(
    itemId: 'movie',
    mediaSourceId: 'source',
    width: 100,
    height: 50,
    tileWidth: 4,
    tileHeight: 2,
    thumbnailCount: 10,
    intervalMs: 10000,
    sheetCount: 2,
    sheetUrlTemplate: '/sprites/{sheetIndex}.jpg',
  );

  test('parses normalized manifest fields', () {
    final parsed = TrickplayManifest.fromJson({
      'itemId': 'movie',
      'mediaSourceId': 'source',
      'width': 100,
      'height': 50,
      'tileWidth': 4,
      'tileHeight': 2,
      'thumbnailCount': 10,
      'intervalMs': 10000,
      'sheetCount': 2,
      'sheetUrlTemplate': '/sprites/{sheetIndex}.jpg',
    });

    expect(parsed.thumbnailsPerSheet, 8);
    expect(
      parsed.sheetUrl(1, 'https://example.test/api'),
      'https://example.test/sprites/1.jpg',
    );
  });

  test('maps time to a cropped tile and clamps the final frame', () {
    final frame = manifest.frameAt(const Duration(seconds: 85));
    expect(frame.index, 8);
    expect(frame.sheetIndex, 1);
    expect(frame.sourceX, 0);
    expect(frame.sourceY, 0);

    final finalFrame = manifest.frameAt(const Duration(hours: 1));
    expect(finalFrame.index, 9);
    expect(finalFrame.sourceX, 100);
    expect(finalFrame.time, const Duration(seconds: 90));
  });
}
