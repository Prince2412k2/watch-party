import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/player/player_chrome.dart';
import 'package:watchparty/player/player_view.dart';
import 'package:watchparty/player/player_controller.dart';
import 'package:watchparty/player/video_view.dart';
import 'package:watchparty/player/media_kit_player_controller.dart';
import 'package:watchparty/analog/player/auto_hide_controller.dart';
import 'package:watchparty/player/party_track_mapping.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/playback_info.dart';
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
  Completer<void>? nextAudioGate;

  final _tracksCtrl = StreamController<PlayerTracks>.broadcast();
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();

  void emitTracks(PlayerTracks t) => _tracksCtrl.add(t);
  void emitPosition(Duration position) => _positionCtrl.add(position);
  void emitPlaying(bool playing) => _playingCtrl.add(playing);

  /// Whether the chrome is still subscribed to this controller's streams.
  bool get isBound => _positionCtrl.hasListener || _tracksCtrl.hasListener;

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
  @override
  Future<void> setRate(double rate) async => rates.add(rate);
  @override
  Future<void> setAudioTrack(String? trackId) async {
    audioTracks.add(trackId);
    final gate = nextAudioGate;
    nextAudioGate = null;
    if (gate != null) await gate.future;
  }

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
  Future<void> dispose() async {
    await _tracksCtrl.close();
    await _positionCtrl.close();
    await _playingCtrl.close();
  }

  @override
  Stream<Duration> get position => _positionCtrl.stream;
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get playing => _playingCtrl.stream;
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<PlayerTracks> get tracks => _tracksCtrl.stream;

  @override
  Duration positionNow = Duration.zero;
  @override
  Duration get durationNow => const Duration(minutes: 90);
  @override
  bool get isPlayingNow => false;
  @override
  bool get isBufferingNow => false;
}

class _NativeSubtitleController extends _SpyController
    implements MediaKitPlayerController {
  bool failSubtitle = false;
  int loads = 0;
  Completer<void>? loadGate;
  String nativeTrackId = 'subtitle data, not a native track ID';
  String? selectedNativeTrack;
  List<PlayerTrack> nativeTracks = const [];
  bool ignoreNativeSelection = false;

  @override
  Future<void> addExternalSubtitle(
    String data, {
    String? title,
    String? language,
  }) async {
    loads++;
    await loadGate?.future;
    if (failSubtitle) throw StateError('Native subtitle load failed');
    selectedNativeTrack = nativeTrackId;
  }

  @override
  Future<void> setSubtitle(String? trackId) async {
    await super.setSubtitle(trackId);
    // Match the real controller: unknown IDs silently leave selection alone.
    if (trackId == null ||
        (!ignoreNativeSelection &&
            nativeTracks.any((track) => track.id == trackId))) {
      selectedNativeTrack = trackId;
    }
  }

  @override
  String? get lastError => null;
  @override
  PlayerTracks get latestTracks => PlayerTracks(subtitle: nativeTracks);
  @override
  double get volumeNow => 100;
  @override
  String? get currentAudioTrackId => null;
  @override
  String? get currentSubtitleTrackId => selectedNativeTrack;
  @override
  bool get hardwareDecodingEnabled => true;
  @override
  double get subtitleScale => 1;
  @override
  int get subtitlePosition => 100;
  @override
  double get subtitleDelay => 0;
  @override
  String get subtitleFont => 'sans-serif';
  @override
  String get subtitleColor => '#FFFFFF';
  @override
  int get subtitleBackgroundOpacity => 65;
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MutableSubtitleApi extends MockApiClient {
  PlaybackInfo info = const PlaybackInfo(
    subtitleStreams: [
      PlaybackTrack(index: 4, title: 'Uploaded', isExternal: true),
    ],
  );
  String content = '00:00:01.000 --> 00:00:03.000\nFirst';
  int contentCalls = 0;

  @override
  Future<PlaybackInfo> playbackInfo(
    String itemId, {
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async => info;

  @override
  Future<String> subtitleContent(
    String itemId,
    int streamIndex, {
    String? mediaSourceId,
  }) async {
    contentCalls++;
    return content;
  }
}

class _GatedSubtitleApi extends MockApiClient {
  final requests = <Completer<PlaybackInfo>>[];

  @override
  Future<PlaybackInfo> playbackInfo(
    String itemId, {
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final request = Completer<PlaybackInfo>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<String> subtitleContent(
    String itemId,
    int streamIndex, {
    String? mediaSourceId,
  }) async => '00:00:01.000 --> 00:00:03.000\nNewest';
}

void main() {
  for (final key in [
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyJ,
    LogicalKeyboardKey.keyL,
    null,
  ]) {
    testWidgets('delegated seek is awaited without local writes: $key', (
      tester,
    ) async {
      final c = _SpyController()..positionNow = const Duration(seconds: 30);
      final gate = Completer<void>();
      final seeks = <Duration>[];
      final reports = <Duration>[];
      var wakes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerView(
            controller: c,
            visible: true,
            onWake: () => wakes++,
            onSeekAuthored: reports.add,
            onSeek: (position) async {
              seeks.add(position);
              await gate.future;
            },
          ),
        ),
      );
      await tester.pump();
      if (key == null) {
        await tester.drag(
          find.byKey(const Key('playbackScrubber')),
          const Offset(100, 0),
        );
      } else {
        await tester.sendKeyEvent(key);
      }
      await tester.pump();
      expect(seeks, hasLength(1));
      expect(c.seeks, isEmpty);
      expect(reports, isEmpty);
      final pendingWakes = wakes;
      gate.complete();
      await tester.pump();
      expect(wakes, pendingWakes + 1);
      expect(c.seeks, isEmpty);
      expect(reports, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await c.dispose();
    });
  }

  test('movies preserve their full frame by default', () {
    expect(VideoView(controller: _SpyController()).fit, BoxFit.contain);
  });

  for (final release in ['focus', 'lifecycle', 'dispose', 'key up']) {
    testWidgets('PTT releases once on $release', (tester) async {
      final c = _SpyController();
      final otherFocus = FocusNode();
      addTearDown(otherFocus.dispose);
      var starts = 0;
      var stops = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                PlayerChrome(
                  controller: c,
                  onPushToTalkStart: () => starts++,
                  onPushToTalkStop: () => stops++,
                ),
                Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 200,
                    child: TextField(focusNode: otherFocus),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
      expect(starts, 1);
      switch (release) {
        case 'focus':
          otherFocus.requestFocus();
          await tester.pump();
        case 'lifecycle':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
        case 'dispose':
          await tester.pumpWidget(const SizedBox.shrink());
        case 'key up':
          break;
      }
      if (release != 'key up') expect(stops, 1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
      expect(stops, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(stops, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await c.dispose();
    });
  }

  testWidgets('unowned T release never calls mic stop', (tester) async {
    var stops = 0;
    final c = _SpyController();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerChrome(controller: c, onPushToTalkStop: () => stops++),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(stops, 0);
    await c.dispose();
  });

  testWidgets('parent auto-hide stays held throughout an open settings menu', (
    tester,
  ) async {
    final c = _SpyController();
    final hide = AnalogAutoHideController();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerChrome(
          controller: c,
          visible: true,
          onHold: hide.hold,
          onRelease: hide.release,
          onWake: () => hide.noteInput(PlayerInputKind.pointer),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump(const Duration(seconds: 4));
    expect(hide.holds, contains('settingsStack'));
    expect(hide.visible, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(hide.holds, isEmpty);
    await tester.pump(const Duration(seconds: 4));
    expect(hide.visible, isFalse);
    hide.dispose();
    await c.dispose();
  });

  for (final fail in [false, true]) {
    testWidgets(
      'external subtitles use only ${fail ? 'fallback after failure' : 'native rendering'}',
      (tester) async {
        final c = _NativeSubtitleController()
          ..failSubtitle = fail
          ..positionNow = const Duration(seconds: 2)
          ..loadGate = Completer<void>();
        final api = _MutableSubtitleApi();
        if (!fail) api.content = '[Script Info]\nTitle: Native ASS';
        await tester.pumpWidget(
          MaterialApp(
            home: PlayerChrome(
              controller: c,
              itemId: 'movie',
              apiClient: api,
              preferredSubtitleStreamIndex: 4,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(c.loads, 1);
        expect(
          find.byKey(const Key('externalSubtitleOverlay')),
          findsNothing,
          reason: 'a pending native load is not a failure',
        );
        c.loadGate!.complete();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('externalSubtitleOverlay')),
          fail ? findsOneWidget : findsNothing,
        );
        expect(c.subtitles, fail ? [null] : isEmpty);
        if (fail) {
          expect(
            tester
                .getBottomLeft(find.byKey(const Key('externalSubtitleOverlay')))
                .dy,
            lessThan(tester.getTopLeft(find.byIcon(Icons.settings)).dy),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await c.dispose();
      },
    );
  }

  for (final scenario in [
    'data ID',
    'native ID',
    'native no-op',
    'reload failure',
  ]) {
    testWidgets('external subtitle Off then reselect: $scenario', (
      tester,
    ) async {
      final selectable = scenario == 'native ID' || scenario == 'native no-op';
      final c = _NativeSubtitleController()
        ..positionNow = const Duration(seconds: 2)
        ..ignoreNativeSelection = scenario == 'native no-op';
      if (selectable) {
        c.nativeTrackId = '7';
        c.nativeTracks = const [
          PlayerTrack(id: '7', type: 'subtitle', title: 'Uploaded'),
        ];
      }
      final api = _MutableSubtitleApi();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerChrome(
            controller: c,
            itemId: 'movie',
            apiClient: api,
            preferredSubtitleStreamIndex: 4,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.selectedNativeTrack, c.nativeTrackId);
      await tester.tap(find.byIcon(Icons.subtitles));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      expect(c.selectedNativeTrack, isNull);
      c.failSubtitle = scenario == 'reload failure';
      await tester.tap(find.byIcon(Icons.subtitles));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Uploaded'));
      await tester.pumpAndSettle();
      expect(c.selectedNativeTrack, c.failSubtitle ? isNull : c.nativeTrackId);
      expect(c.loads, scenario == 'native ID' ? 1 : 2);
      expect(api.contentCalls, 1);
      expect(
        find.byKey(const Key('externalSubtitleOverlay')),
        c.failSubtitle ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await c.dispose();
    });
  }
  test(
    'Jellyfin global indices map by metadata then preserve subtitle off',
    () {
      const playback = PlaybackInfo(
        audioStreams: [
          PlaybackTrack(
            index: 1,
            title: 'English',
            language: 'eng',
            codec: 'aac',
          ),
          PlaybackTrack(
            index: 5,
            title: 'Commentary',
            language: 'eng',
            codec: 'aac',
          ),
        ],
        subtitleStreams: [
          PlaybackTrack(
            index: 7,
            title: 'English SDH',
            language: 'eng',
            codec: 'subrip',
          ),
        ],
      );
      const nativeAudio = [
        PlayerTrack(
          id: '2',
          type: 'audio',
          title: 'Commentary',
          language: 'eng',
          codec: 'aac',
        ),
        PlayerTrack(
          id: '1',
          type: 'audio',
          title: 'English',
          language: 'eng',
          codec: 'aac',
        ),
      ];
      expect(
        playerTrackIdForJellyfinIndex(
          jellyfinIndex: 5,
          type: 'audio',
          playerTracks: nativeAudio,
          playback: playback,
        ),
        '2',
      );
      expect(
        jellyfinIndexForPlayerTrack(
          playerTrackId: null,
          type: 'subtitle',
          playerTracks: const [],
          playback: playback,
        ),
        -1,
      );
    },
  );

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

  /// Opens the audio-track picker.
  ///
  /// Two taps now, not one. Audio used to be its own button in the transport
  /// bar; it lives inside the settings stack behind the gear, because the
  /// bottom bar is subtitle / mute / gear / fullscreen and audio is not a
  /// per-minute control. The direct SUBTITLE control deliberately stays out
  /// there — Off and a track swap must not cost two taps — which is why these
  /// tests reach subtitles and audio by different routes.
  Future<void> openAudioPicker(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Audio track'));
    await tester.pumpAndSettle();
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

  // The volume control is now a VERTICAL hairline near the right edge rather
  // than a 76px horizontal slider inside the transport row, so the drag that
  // lowers it is downward.
  testWidgets('dragging the volume control calls setVolume', (tester) async {
    final c = _SpyController();
    await pumpChrome(tester, c);

    await tester.drag(
      find.byKey(const Key('volumeSlider')),
      const Offset(0, 40),
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

  testWidgets('external subtitle overlay follows playback and clears on Off', (
    tester,
  ) async {
    final c = _SpyController();
    final api = MockApiClient(
      playback: const PlaybackInfo(
        subtitleStreams: [
          PlaybackTrack(index: 4, title: 'Uploaded English', isExternal: true),
        ],
      ),
      subtitleContents: const {
        4:
            '00:00:01.000 --> 00:00:03.000\nFirst\n\n'
            '00:00:01.500 --> 00:00:02.500\nSecond',
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PlayerChrome(
            controller: c,
            itemId: 'movie',
            apiClient: api,
            preferredSubtitleStreamIndex: 4,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    c.emitPosition(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('externalSubtitleOverlay')), findsOneWidget);
    expect(find.text('First\nSecond'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('First\nSecond')).dy,
      lessThan(tester.getTopLeft(find.byIcon(Icons.settings)).dy),
    );

    await tester.tap(find.byIcon(Icons.subtitles));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('externalSubtitleOverlay')), findsNothing);
    expect(c.subtitles, [null, null]);
  });

  testWidgets('subtitle revision replaces same-index cached content', (
    tester,
  ) async {
    final c = _SpyController();
    final api = _MutableSubtitleApi();

    Widget chrome(int revision) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: PlayerChrome(
          controller: c,
          itemId: 'movie',
          apiClient: api,
          preferredSubtitleStreamIndex: 4,
          subtitleRevision: revision,
        ),
      ),
    );

    await tester.pumpWidget(chrome(1));
    await tester.pumpAndSettle();
    c.emitPosition(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();
    expect(find.text('First'), findsOneWidget);

    api.content = '00:00:01.000 --> 00:00:03.000\nSecond';
    await tester.pumpWidget(chrome(2));
    await tester.pumpAndSettle();
    c.emitPosition(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();

    expect(find.text('Second'), findsOneWidget);
    expect(api.contentCalls, 2);
  });

  testWidgets('an older subtitle request cannot overwrite a newer revision', (
    tester,
  ) async {
    final c = _SpyController();
    final api = _GatedSubtitleApi();
    const playback = PlaybackInfo(
      subtitleStreams: [
        PlaybackTrack(index: 4, title: 'Uploaded', isExternal: true),
      ],
    );

    Widget chrome(int revision) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: PlayerChrome(
          controller: c,
          itemId: 'movie',
          apiClient: api,
          preferredSubtitleStreamIndex: 4,
          subtitleRevision: revision,
        ),
      ),
    );

    await tester.pumpWidget(chrome(1));
    await tester.pump();
    await tester.pumpWidget(chrome(2));
    await tester.pump();
    expect(api.requests, hasLength(2));

    api.requests[1].complete(playback);
    await tester.pumpAndSettle();
    c.emitPosition(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();
    expect(find.text('Newest'), findsOneWidget);

    api.requests[0].complete(const PlaybackInfo());
    await tester.pumpAndSettle();
    expect(find.text('Newest'), findsOneWidget);
  });

  testWidgets('an older canonical track apply stops after delayed audio', (
    tester,
  ) async {
    final oldAudioGate = Completer<void>();
    final c = _SpyController()..nextAudioGate = oldAudioGate;
    final api = _GatedSubtitleApi();
    const tracks = PlayerTracks(
      audio: [
        PlayerTrack(
          id: 'audio-old',
          type: 'audio',
          title: 'Old audio',
          jellyfinIndex: 1,
        ),
        PlayerTrack(
          id: 'audio-new',
          type: 'audio',
          title: 'New audio',
          jellyfinIndex: 2,
        ),
      ],
      subtitle: [
        PlayerTrack(
          id: 'sub-old',
          type: 'subtitle',
          title: 'Old subtitle',
          jellyfinIndex: 3,
        ),
        PlayerTrack(
          id: 'sub-new',
          type: 'subtitle',
          title: 'New subtitle',
          jellyfinIndex: 4,
        ),
      ],
    );

    Widget chrome(int revision) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: PlayerChrome(
          controller: c,
          itemId: 'movie',
          apiClient: api,
          subtitleRevision: revision,
        ),
      ),
    );

    await tester.pumpWidget(chrome(1));
    await tester.pump();
    c.emitTracks(tracks);
    api.requests[0].complete(
      const PlaybackInfo(
        selectedAudioIndex: 1,
        selectedSubtitleIndex: 3,
        audioStreams: [PlaybackTrack(index: 1, title: 'Old audio')],
        subtitleStreams: [PlaybackTrack(index: 3, title: 'Old subtitle')],
      ),
    );
    await tester.pump();

    await tester.pumpWidget(chrome(2));
    await tester.pump();
    api.requests[1].complete(
      const PlaybackInfo(
        selectedSubtitleIndex: 4,
        subtitleStreams: [PlaybackTrack(index: 4, title: 'New subtitle')],
      ),
    );
    await tester.pumpAndSettle();
    expect(c.subtitles, contains('sub-new'));

    oldAudioGate.complete();
    await tester.pumpAndSettle();
    expect(c.subtitles.last, 'sub-new');
    expect(c.subtitles, isNot(contains('sub-old')));
  });

  testWidgets(
    'subtitle menu deduplicates Jellyfin and native representations',
    (tester) async {
      final c = _SpyController();
      final api = MockApiClient(
        playback: const PlaybackInfo(
          subtitleStreams: [
            PlaybackTrack(
              index: 4,
              title: 'English - SUBRIP - External',
              language: 'eng',
              codec: 'subrip',
              isExternal: true,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: PlayerChrome(controller: c, itemId: 'movie', apiClient: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.emitTracks(
        const PlayerTracks(
          subtitle: [
            PlayerTrack(
              id: 'native-sidecar',
              type: 'subtitle',
              title: 'English - SUBRIP - External',
              language: 'eng',
              codec: 'subrip',
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byIcon(Icons.subtitles));
      await tester.pump();
      expect(find.text('English - SUBRIP - External'), findsOneWidget);
    },
  );

  testWidgets('audio menu calls setAudioTrack', (tester) async {
    final c = _SpyController();
    await pumpChrome(tester, c);
    c.emitTracks(tracks);
    await tester.pump(); // deliver stream event (schedules setState)
    await tester.pump(); // rebuild with the new tracks

    await openAudioPicker(tester);
    // The picker grows UPWARD out of the transport bar. This is the
    // bottom-right corner, so a menu opening downward would run off the
    // window; it must also not extend past its own anchor and cover the
    // controls beside it. Bounded by the gear's BOTTOM rather than its top —
    // overlapping the button you just pressed is fine and unavoidable, since
    // that is what the menu hangs off.
    expect(
      tester.getBottomLeft(find.text('Commentary')).dy,
      lessThanOrEqualTo(tester.getBottomLeft(find.byIcon(Icons.settings)).dy),
    );
    await tester.tap(find.text('Commentary'));
    await tester.pumpAndSettle();
    expect(c.audioTracks, ['a1']);
  });

  testWidgets(
    'party track callbacks receive Jellyfin indices without local writes',
    (tester) async {
      final c = _SpyController();
      final audio = <int?>[];
      final subtitles = <int?>[];
      final api = MockApiClient(
        playback: const PlaybackInfo(
          audioStreams: [PlaybackTrack(index: 8, title: 'Commentary')],
          subtitleStreams: [PlaybackTrack(index: 12, title: 'English SDH')],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: PlayerChrome(
              controller: c,
              itemId: 'movie',
              apiClient: api,
              onAudioStreamSelected: (index) async => audio.add(index),
              onSubtitleStreamSelected: (index) async => subtitles.add(index),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.emitTracks(
        const PlayerTracks(
          audio: [
            PlayerTrack(
              id: 'a1',
              type: 'audio',
              title: 'Commentary',
              jellyfinIndex: 8,
            ),
          ],
          subtitle: [
            PlayerTrack(
              id: 's1',
              type: 'subtitle',
              title: 'English SDH',
              jellyfinIndex: 12,
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      await openAudioPicker(tester);
      await tester.tap(find.text('Commentary'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.subtitles));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();

      expect(audio, [8]);
      expect(subtitles, [-1]);
      expect(c.audioTracks, isEmpty);
      expect(c.subtitles, isEmpty);
    },
  );

  testWidgets(
    'preferred embedded subtitle is applied from canonical party state',
    (tester) async {
      final c = _SpyController();
      final api = MockApiClient(
        playback: const PlaybackInfo(
          subtitleStreams: [PlaybackTrack(index: 12, title: 'English SDH')],
          selectedSubtitleIndex: -1,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: PlayerChrome(
              controller: c,
              itemId: 'movie',
              apiClient: api,
              preferredSubtitleStreamIndex: 12,
              onSubtitleStreamSelected: (_) async {},
            ),
          ),
        ),
      );
      c.emitTracks(
        const PlayerTracks(
          subtitle: [
            PlayerTrack(
              id: 's1',
              type: 'subtitle',
              title: 'English SDH',
              jellyfinIndex: 12,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(c.subtitles, contains('s1'));
    },
  );

  testWidgets('guest can select local audio and subtitle tracks', (
    tester,
  ) async {
    final c = _SpyController();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: PlayerChrome(controller: c, canControl: false)),
      ),
    );
    c.emitTracks(tracks);
    await tester.pump();
    await tester.pump();

    await openAudioPicker(tester);
    await tester.tap(find.text('Commentary'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.subtitles));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English SDH'));
    await tester.pumpAndSettle();

    expect(c.audioTracks, ['a1']);
    expect(c.subtitles, ['s0']);
    expect(c.seeks, isEmpty);
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

    // Audio moved inside the settings stack, so asserting its ICON is absent
    // would now pass for the wrong reason — the row is unbuilt until the gear
    // is open, whether or not there are tracks. Open the stack and assert the
    // ROW is missing, which is the thing the test was always about.
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text('Audio track'), findsNothing);
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

  // ── #67: the analog control kit, wired end to end ───────────────────────

  // `keyC` used to be matched on the logical key ALONE and returned `handled`,
  // so Ctrl+C / Cmd+C toggled chat and swallowed the platform copy. The guard
  // is analog/player_core.dart's shouldToggleChat, shared with React.
  testWidgets('Ctrl+C toggles chat, and never at the cost of copy', (
    tester,
  ) async {
    final c = _SpyController();
    var chatToggles = 0;
    var pttStarts = 0;
    var pttStops = 0;
    var fullscreenToggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PlayerChrome(
            controller: c,
            onToggleChat: () => chatToggles++,
            onPushToTalkStart: () => pttStarts++,
            onPushToTalkStop: () => pttStops++,
            onToggleFullscreen: () => fullscreenToggles++,
          ),
        ),
      ),
    );
    await tester.pump();

    // Bare `c` keeps working.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(chatToggles, 1);

    // Ctrl+C with nothing selected is the analog chat shortcut.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(chatToggles, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.pump();
    expect(fullscreenToggles, 1);

    // Every OTHER accelerator the player used to swallow is left to the
    // platform: Ctrl+T is a new window, not push-to-talk.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(pttStarts, 0);
    expect(pttStops, 0);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    expect(pttStarts, 1);
    expect(pttStops, 1);
  });

  testWidgets('Ctrl+C inside a text field leaves copy alone', (tester) async {
    final c = _SpyController();
    var chatToggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: PlayerChrome(
                  controller: c,
                  onToggleChat: () => chatToggles++,
                ),
              ),
              const TextField(key: Key('composer')),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer')));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(chatToggles, 0);
  });

  // Volume, mute and fullscreen BUTTONS were always ungated (volume is a
  // personal setting), but their keys sat behind canControl, so a read-only
  // guest's ↑/↓/M did nothing while the same guest's slider worked.
  testWidgets('a read-only guest can still work volume from the keyboard', (
    tester,
  ) async {
    final c = _SpyController();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: PlayerChrome(controller: c, canControl: false)),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.volumes, [90.0]);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(c.volumes, [90.0, 0.0]);

    // Transport keys stay gated.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.seeks, isEmpty);
  });

  // The player no longer renders chat toasts. It drew them at the top left,
  // INSIDE the party screen's stage — underneath the floating camera tiles —
  // so a message could arrive behind a participant's face. There is one
  // notification path now, the app-wide rail above the router, and its
  // behaviour is covered by test/chat_notifications_test.dart: the notice
  // itself, the drawer-open suppression that used to live here, own-message
  // filtering, and the backlog-at-mount rule.
  //
  // player_core's toast queue (three deep, own clock, collapsed count) is
  // still shared byte-for-byte with React and still covered by the
  // interaction-parity cases; only this widget's rendering of it is gone.

  // Solo playback used to run its own idle Timer here while the party screen
  // ran a second one; both now drive AnalogAutoHideController, which is
  // analog/player_core.dart's machine.
  testWidgets('self-managed chrome hides three seconds into playback and '
      'returns on input', (tester) async {
    final c = _SpyController();
    await pumpChrome(tester, c);

    final transport = find.ancestor(
      of: find.byKey(const Key('playbackScrubber')),
      matching: find.byType(AnimatedOpacity),
    );
    double opacity() => tester.widget<AnimatedOpacity>(transport.first).opacity;

    // Paused: nothing to hide from.
    await tester.pump(const Duration(seconds: 10));
    expect(opacity(), 1);

    c.emitPlaying(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(opacity(), 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(opacity(), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(opacity(), 1);
  });

  testWidgets('parent-owned visibility still wins and forwards every wake', (
    tester,
  ) async {
    final c = _SpyController();
    var wakes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: PlayerChrome(
            controller: c,
            visible: false,
            onWake: () => wakes++,
          ),
        ),
      ),
    );
    await tester.pump();
    final transport = find.ancestor(
      of: find.byKey(const Key('playbackScrubber')),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(transport.first).opacity, 0);

    c.emitPlaying(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    // Still hidden: the parent owns the flag, and this chrome never overrides.
    expect(tester.widget<AnimatedOpacity>(transport.first).opacity, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(wakes, greaterThan(0));
  });

  // A replaced controller used to leave the chrome subscribed to the old
  // player: it kept mirroring a position/track set nobody was watching, while
  // every control wrote to the new one (audit #61).
  testWidgets('replacing the controller unbinds the old player and seeds '
      'the new one', (tester) async {
    final first = _SpyController();
    final second = _SpyController()..positionNow = const Duration(minutes: 10);
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    Widget chrome(_SpyController c) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: PlayerChrome(controller: c)),
    );

    await tester.pumpWidget(chrome(first));
    await tester.pump();
    first.emitPosition(const Duration(minutes: 3));
    await tester.pump(); // deliver the stream event (schedules setState)
    await tester.pump(); // rebuild with it
    expect(find.text('3:00 / 1:30:00'), findsOneWidget);
    expect(first.isBound, isTrue);

    await tester.pumpWidget(chrome(second));
    await tester.pump();

    // Seeded from the replacement's own state, not carried over from the old.
    expect(find.text('10:00 / 1:30:00'), findsOneWidget);
    expect(first.isBound, isFalse);
    expect(second.isBound, isTrue);

    // The old player can no longer move the chrome…
    first.emitPosition(const Duration(minutes: 40));
    await tester.pump();
    await tester.pump();
    expect(find.text('10:00 / 1:30:00'), findsOneWidget);

    // …and the new one can, on every stream the chrome reads.
    second.emitPosition(const Duration(minutes: 20));
    second.emitTracks(tracks);
    await tester.pump();
    await tester.pump();
    expect(find.text('20:00 / 1:30:00'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.subtitles));
    await tester.pumpAndSettle();
    expect(find.text('English SDH'), findsOneWidget);
  });
}
