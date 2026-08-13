import 'dart:math';

/// Which of the three moments in a playback session this is.
///
/// They are not interchangeable. [started] opens the session; [progress] moves
/// the position along; [stopped] is the one Jellyfin derives the resume point
/// and the played flag from, so a session that never sends it leaves the title
/// stuck at whatever the last tick happened to say.
enum PlaybackReportKind {
  started('started'),
  progress('progress'),
  stopped('stopped');

  const PlaybackReportKind(this.path);

  /// The `/api/playback/<path>` route this posts to.
  final String path;
}

/// One playback report: where this viewer is in this title, right now.
///
/// Hand-written rather than frozen because it is a wire body with no domain
/// behaviour, and because it has to survive a round trip through the offline
/// queue's JSON — [toJson]/[fromJson] are both halves of that.
class PlaybackReport {
  const PlaybackReport({
    required this.itemId,
    required this.positionTicks,
    this.mediaSourceId,
    this.playSessionId,
    this.isPaused = false,
  });

  final String itemId;

  /// Jellyfin's unit: 100-nanosecond ticks. Build it with
  /// [PlaybackReport.ticksOf] rather than by hand — the conversion from a Dart
  /// [Duration] is one multiplication and easy to get an order of magnitude
  /// wrong, which lands the resume point in the wrong scene rather than
  /// throwing anything.
  final int positionTicks;

  final String? mediaSourceId;

  /// Ties this session's three reports together for Jellyfin.
  ///
  /// Minted by the client, not by Jellyfin's PlaybackInfo. We never open a
  /// Jellyfin stream session — `native.js` serves the file itself — so there is
  /// no server-side session id to inherit; this exists purely so Jellyfin can
  /// see one play rather than a stream of unrelated positions.
  final String? playSessionId;

  final bool isPaused;

  /// A [Duration] in Jellyfin ticks.
  static int ticksOf(Duration position) => position.inMicroseconds * 10;

  /// Jellyfin ticks back to a [Duration] — the inverse, for a resume point read
  /// off `UserData.playbackPositionTicks`.
  static Duration durationOf(int ticks) =>
      Duration(microseconds: (ticks / 10).round());

  /// A fresh session id. Not a real UUID and does not need to be: it only has
  /// to be unlikely to collide with another play in flight.
  static String newSessionId() {
    final random = Random.secure();
    return List.generate(
      4,
      (_) => random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    ).join();
  }

  PlaybackReport copyWith({int? positionTicks, bool? isPaused}) =>
      PlaybackReport(
        itemId: itemId,
        positionTicks: positionTicks ?? this.positionTicks,
        mediaSourceId: mediaSourceId,
        playSessionId: playSessionId,
        isPaused: isPaused ?? this.isPaused,
      );

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'positionTicks': positionTicks,
    if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
    if (playSessionId != null) 'playSessionId': playSessionId,
    'isPaused': isPaused,
  };

  static PlaybackReport? fromJson(Map<String, dynamic> json) {
    final itemId = json['itemId'];
    final ticks = json['positionTicks'];
    if (itemId is! String || ticks is! int) return null;
    return PlaybackReport(
      itemId: itemId,
      positionTicks: ticks,
      mediaSourceId: json['mediaSourceId'] as String?,
      playSessionId: json['playSessionId'] as String?,
      isPaused: json['isPaused'] == true,
    );
  }
}
