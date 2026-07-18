import '../models/playback_info.dart';
import 'player_controller.dart';

String? playerTrackIdForJellyfinIndex({
  required int? jellyfinIndex,
  required String type,
  required List<PlayerTrack> playerTracks,
  required PlaybackInfo playback,
}) {
  if (jellyfinIndex == null || jellyfinIndex < 0) return null;
  final streams = type == 'audio'
      ? playback.audioStreams
      : playback.subtitleStreams;
  final target = streams.where((s) => s.index == jellyfinIndex).firstOrNull;
  if (target == null) return null;
  for (final track in playerTracks) {
    if (track.jellyfinIndex == jellyfinIndex) return track.id;
  }
  final nativeStreams = streams.where((s) => !s.isExternal).toList();
  final nativeOrdinal = nativeStreams.indexWhere((s) => s.index == jellyfinIndex);
  if (nativeOrdinal < 0) return null;

  final scored = [
    for (var i = 0; i < playerTracks.length; i++)
      (track: playerTracks[i], score: _score(playerTracks[i], target), index: i),
  ]..sort((a, b) => b.score.compareTo(a.score));
  if (scored.isNotEmpty &&
      scored.first.score >= 4 &&
      (scored.length == 1 || scored.first.score > scored[1].score)) {
    return scored.first.track.id;
  }
  return nativeOrdinal < playerTracks.length
      ? playerTracks[nativeOrdinal].id
      : null;
}

int? jellyfinIndexForPlayerTrack({
  required String? playerTrackId,
  required String type,
  required List<PlayerTrack> playerTracks,
  required PlaybackInfo playback,
}) {
  if (playerTrackId == null) return type == 'subtitle' ? -1 : null;
  final playerIndex = playerTracks.indexWhere((t) => t.id == playerTrackId);
  if (playerIndex < 0) return null;
  final track = playerTracks[playerIndex];
  if (track.jellyfinIndex != null) return track.jellyfinIndex;
  final streams = (type == 'audio'
      ? playback.audioStreams
      : playback.subtitleStreams).where((s) => !s.isExternal).toList();
  if (streams.isEmpty) return null;
  final scored = [
    for (final stream in streams) (stream: stream, score: _score(track, stream)),
  ]..sort((a, b) => b.score.compareTo(a.score));
  if (scored.first.score >= 4 &&
      (scored.length == 1 || scored.first.score > scored[1].score)) {
    return scored.first.stream.index;
  }
  return playerIndex < streams.length ? streams[playerIndex].index : null;
}

int _score(PlayerTrack track, PlaybackTrack stream) {
  var score = 0;
  if (_same(track.codec, stream.codec)) score += 3;
  if (_same(track.language, stream.language)) score += 2;
  final streamTitle = stream.displayTitle ?? stream.title;
  if (_same(track.title, streamTitle)) score += 4;
  if (track.isDefault == stream.isDefault) score += 1;
  return score;
}

bool _same(String? a, String? b) =>
    a != null && b != null && a.trim().toLowerCase() == b.trim().toLowerCase();
