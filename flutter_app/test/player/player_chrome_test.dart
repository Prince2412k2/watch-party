import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/player/player_chrome.dart';
import 'package:watchparty/player/player_controller.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/trickplay_manifest.dart';
import 'package:watchparty/ui/ui.dart';

/// Records every write the chrome makes to the controller so the tests can
/// assert each transport control is actually wired to the real player API
/// (the class of bug this work targets: UI callbacks that never reach the
/// controller).
class _SpyController implements PlayerController {
  final volumes = <double>[];
  final rates = <double>[];
  final audioTracks = <String?>[];
  final subtitles = <String?>[];
  final seeks = <Duration>[];

  final _tracksCtrl = StreamController<PlayerTracks>.broadcast();

  void emitTracks(PlayerTracks t) => _tracksCtrl.add(t);

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
  @override
  Future<void> setRate(double rate) async => rates.add(rate);
  @override
  Future<void> setAudioTrack(String? trackId) async => audioTracks.add(trackId);
  @override
  Future<void> setSubtitle(String? trackId) async => subtitles.add(trackId);

  @override
  Future<void> open(
    String url, {
    Duration startAt = Duration.zero,
    bool autoplay = false,
  }) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
  @override
  Future<void> dispose() async => _tracksCtrl.close();

  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<PlayerTracks> get tracks => _tracksCtrl.stream;

  @override
  Duration get positionNow => Duration.zero;
  @override
  Duration get durationNow => const Duration(minutes: 90);
  @override
  bool get isPlayingNow => false;
  @override
  bool get isBufferingNow => false;
}

void main() {
  Future<void> pumpChrome(WidgetTester tester, _SpyController c) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PlayerChrome(controller: c, onToggleFullscreen: () {}),
        ),
      ),
    );
    await tester.pump();
  }

  const tracks = PlayerTracks(
    audio: [
      PlayerTrack(id: 'a0', type: 'audio', title: 'English'),
      PlayerTrack(id: 'a1', type: 'audio', title: 'Commentary'),
    ],
    subtitle: [PlayerTrack(id: 's0', type: 'subtitle', title: 'English SDH')],
  );

  testWidgets('mute toggle calls setVolume(0) then restores the prior level', (
    tester,
  ) async {
    final c = _SpyController();
    await pumpChrome(tester, c);

    // Default (non-media_kit) starting volume is 100 → shows a Mute affordance.
    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(c.volumes, [0.0]);

    // Now muted → the same button unmutes back to the pre-mute level (100),
    // not a hard jump that ignores the previous value.
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();
    expect(c.volumes, [0.0, 100.0]);
  });

  testWidgets('dragging the volume slider calls setVolume', (tester) async {
    final c = _SpyController();
    await pumpChrome(tester, c);

    await tester.drag(
      find.byKey(const Key('volumeSlider')),
      const Offset(-40, 0),
    );
    await tester.pump();
    expect(c.volumes, isNotEmpty);
    expect(c.volumes.last, lessThan(100.0));
  });

  testWidgets('speed control is gone; decode + subtitle-settings hidden for a '
      'non-media_kit controller', (tester) async {
    final c = _SpyController();
    await pumpChrome(tester, c);

    // The playback-speed affordance was removed entirely.
    expect(find.byIcon(Icons.speed), findsNothing);

    // Decode (memory) and the subtitle-settings gear (tune) are libmpv-only —
    // guarded behind `is MediaKitPlayerController`, so a spy/mock controller
    // renders neither, and nothing throws.
    expect(find.byIcon(Icons.memory), findsNothing);
    expect(find.byIcon(Icons.tune), findsNothing);
  });

  testWidgets('subtitle menu calls setSubtitle for a track and for Off', (
    tester,
  ) async {
    final c = _SpyController();
    await pumpChrome(tester, c);
    c.emitTracks(tracks);
    await tester.pump(); // deliver stream event (schedules setState)
    await tester.pump(); // rebuild with the new tracks

    await tester.tap(find.byIcon(Icons.subtitles));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English SDH'));
    await tester.pumpAndSettle();
    expect(c.subtitles, ['s0']);

    await tester.tap(find.byIcon(Icons.subtitles));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(c.subtitles, ['s0', null]);
  });

  testWidgets('audio menu calls setAudioTrack', (tester) async {
    final c = _SpyController();
    await pumpChrome(tester, c);
    c.emitTracks(tracks);
    await tester.pump(); // deliver stream event (schedules setState)
    await tester.pump(); // rebuild with the new tracks

    await tester.tap(find.byIcon(Icons.audiotrack));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commentary'));
    await tester.pumpAndSettle();
    expect(c.audioTracks, ['a1']);
  });

  testWidgets('track menus are hidden when the media has no extra tracks', (
    tester,
  ) async {
    final c = _SpyController();
    await pumpChrome(tester, c);
    c.emitTracks(const PlayerTracks());
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.subtitles), findsNothing);
    expect(find.byIcon(Icons.audiotrack), findsNothing);
  });

  testWidgets('read-only guest can hover for a preview without seeking', (
    tester,
  ) async {
    final c = _SpyController();
    const manifest = TrickplayManifest(
      itemId: 'movie',
      mediaSourceId: 'source',
      width: 200,
      height: 100,
      tileWidth: 100,
      tileHeight: 100,
      thumbnailCount: 20,
      intervalMs: 10000,
      sheetCount: 10,
      sheetUrlTemplate: '/sprite/{sheet}.jpg',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PlayerChrome(
            controller: c,
            canControl: false,
            itemId: 'movie',
            apiClient: MockApiClient(trickplayManifest: manifest),
          ),
        ),
      ),
    );
    await tester.pump();
    final scrubber = find.byKey(const Key('playbackScrubber'));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(scrubber));
    await gesture.moveTo(tester.getCenter(scrubber));
    await tester.pump();

    expect(find.text('3:10'), findsOneWidget);
    expect(c.seeks, isEmpty);
    await gesture.removePointer();
  });

  testWidgets('scrubbing commits a single seek when the drag ends', (
    tester,
  ) async {
    final c = _SpyController();
    await pumpChrome(tester, c);

    await tester.drag(
      find.byKey(const Key('playbackScrubber')),
      const Offset(100, 0),
    );
    await tester.pump();

    expect(c.seeks, hasLength(1));
  });
}
