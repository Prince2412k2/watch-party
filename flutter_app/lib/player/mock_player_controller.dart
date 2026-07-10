import 'dart:async';

import 'player_controller.dart';

/// A clockless-but-tickable [PlayerController] mock. It advances position with a
/// real timer while "playing" so the sync engine (E5) and player chrome (E4.2)
/// can be developed and tested without libmpv.
class MockPlayerController implements PlayerController {
  MockPlayerController({Duration duration = const Duration(minutes: 90)})
      // ignore: prefer_initializing_formals
      : _duration = duration {
    _durationCtrl.add(_duration);
  }

  final _positionCtrl = StreamController<Duration>.broadcast();
  final _durationCtrl = StreamController<Duration>.broadcast();
  final _bufferingCtrl = StreamController<bool>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _completedCtrl = StreamController<bool>.broadcast();
  final _tracksCtrl = StreamController<PlayerTracks>.broadcast();

  Duration _position = Duration.zero;
  final Duration _duration;
  bool _playing = false;
  final bool _buffering = false;
  double _rate = 1.0;
  Timer? _ticker;
  bool _disposed = false;

  @override
  Future<void> open(String url,
      {Duration startAt = Duration.zero, bool autoplay = false}) async {
    _position = startAt;
    _positionCtrl.add(_position);
    _tracksCtrl.add(const PlayerTracks(
      audio: [
        PlayerTrack(id: 'a0', type: 'audio', title: 'English', language: 'eng', isDefault: true),
        PlayerTrack(id: 'a1', type: 'audio', title: 'Commentary', language: 'eng'),
      ],
      subtitle: [
        PlayerTrack(id: 's0', type: 'subtitle', title: 'English', language: 'eng'),
      ],
    ));
    if (autoplay) await play();
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    _playing = true;
    _playingCtrl.add(true);
    _ticker ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      _position += Duration(milliseconds: (250 * _rate).round());
      if (_position >= _duration) {
        _position = _duration;
        _completedCtrl.add(true);
        pause();
      }
      _positionCtrl.add(_position);
    });
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _playingCtrl.add(false);
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionCtrl.add(_position);
  }

  @override
  Future<void> setRate(double rate) async => _rate = rate;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setAudioTrack(String? trackId) async {}

  @override
  Future<void> setSubtitle(String? trackId) async {}

  @override
  Future<void> dispose() async {
    _disposed = true;
    _ticker?.cancel();
    await _positionCtrl.close();
    await _durationCtrl.close();
    await _bufferingCtrl.close();
    await _playingCtrl.close();
    await _completedCtrl.close();
    await _tracksCtrl.close();
  }

  @override
  Stream<Duration> get position => _positionCtrl.stream;
  @override
  Stream<Duration> get duration => _durationCtrl.stream;
  @override
  Stream<bool> get buffering => _bufferingCtrl.stream;
  @override
  Stream<bool> get playing => _playingCtrl.stream;
  @override
  Stream<bool> get completed => _completedCtrl.stream;
  @override
  Stream<PlayerTracks> get tracks => _tracksCtrl.stream;

  @override
  Duration get positionNow => _position;
  @override
  Duration get durationNow => _duration;
  @override
  bool get isPlayingNow => _playing;
  @override
  bool get isBufferingNow => _buffering;
}
