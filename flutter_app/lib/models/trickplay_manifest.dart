class TrickplayFrame {
  const TrickplayFrame({
    required this.index,
    required this.sheetIndex,
    required this.sourceX,
    required this.sourceY,
    required this.time,
  });

  final int index;
  final int sheetIndex;
  final int sourceX;
  final int sourceY;
  final Duration time;
}

class TrickplayManifest {
  const TrickplayManifest({
    required this.itemId,
    required this.mediaSourceId,
    required this.width,
    required this.height,
    required this.tileWidth,
    required this.tileHeight,
    required this.thumbnailCount,
    required this.intervalMs,
    required this.sheetCount,
    required this.sheetUrlTemplate,
  });

  factory TrickplayManifest.fromJson(Map<String, dynamic> json) =>
      TrickplayManifest(
        itemId: json['itemId'] as String,
        mediaSourceId: json['mediaSourceId'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
        tileWidth: json['tileWidth'] as int,
        tileHeight: json['tileHeight'] as int,
        thumbnailCount: json['thumbnailCount'] as int,
        intervalMs: json['intervalMs'] as int,
        sheetCount: json['sheetCount'] as int,
        sheetUrlTemplate: json['sheetUrlTemplate'] as String,
      );

  final String itemId;
  final String mediaSourceId;
  final int width;
  final int height;
  final int tileWidth;
  final int tileHeight;
  final int thumbnailCount;
  final int intervalMs;
  final int sheetCount;
  final String sheetUrlTemplate;

  int get columns => tileWidth;
  int get rows => tileHeight;
  int get thumbnailsPerSheet => columns * rows;

  TrickplayFrame frameAt(Duration position) {
    final index = (position.inMilliseconds ~/ intervalMs).clamp(
      0,
      thumbnailCount - 1,
    );
    final indexInSheet = index % thumbnailsPerSheet;
    return TrickplayFrame(
      index: index,
      sheetIndex: index ~/ thumbnailsPerSheet,
      sourceX: (indexInSheet % columns) * width,
      sourceY: (indexInSheet ~/ columns) * height,
      time: Duration(milliseconds: index * intervalMs),
    );
  }

  String sheetUrl(int sheetIndex, String baseUrl) {
    final relative = sheetUrlTemplate
        .replaceAll('{sheetIndex}', '$sheetIndex')
        .replaceAll('{sheet}', '$sheetIndex');
    return Uri.parse(baseUrl).resolve(relative).toString();
  }
}
