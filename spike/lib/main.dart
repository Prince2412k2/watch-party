import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:logging/logging.dart' as logging;

const backend = 'http://localhost:3005';
const itemId = '19e55dfac3a265dff5ee14af05dd0a4c';

final File _logFile =
    File('/home/princepatel/projects/watch_party/spike/run.log');
void log(String m) {
  final line = '[SPIKE] ${DateTime.now().toIso8601String()} $m';
  // ignore: avoid_print
  print(line);
  try {
    _logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  try {
    _logFile.writeAsStringSync('', flush: true);
  } catch (_) {}
  logging.Logger.root.level = logging.Level.ALL;
  logging.Logger.root.onRecord.listen((r) {
    log('LK-LOG ${r.loggerName} ${r.level.name}: ${r.message}');
  });
  log('main() started, MediaKit initialized');
  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'wp_spike',
      theme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Player player = Player();
  late final VideoController controller = VideoController(player);
  String status = 'starting…';
  Duration pos = Duration.zero;
  Duration dur = Duration.zero;

  // S2
  lk.Room? room;
  String roomState = 'not connected';
  final List<lk.VideoTrack> videoTracks = [];

  @override
  void initState() {
    super.initState();
    player.stream.position.listen((p) {
      if (p.inSeconds != pos.inSeconds) log('position=${p.inMilliseconds}ms');
      if (mounted) setState(() => pos = p);
    });
    player.stream.duration.listen((d) {
      if (mounted) setState(() => dur = d);
    });
    player.stream.playing.listen((pl) => log('playing=$pl'));
    player.stream.buffering.listen((b) => log('buffering=$b'));
    player.stream.error.listen((e) => log('PLAYER ERROR: $e'));
    _startPlayback();
    if (Platform.environment['SPIKE_AUTOJOIN'] == '1') {
      Future.delayed(const Duration(seconds: 3), _joinAV);
    }
  }

  Future<void> _startPlayback() async {
    try {
      setState(() => status = 'logging in…');
      final jar = CookieJar();
      final dio = Dio(BaseOptions(baseUrl: backend));
      dio.interceptors.add(CookieManager(jar));

      final loginResp = await dio.post('/api/auth/login',
          data: {'username': 'root', 'password': 'root'});
      log('login OK: ${loginResp.data}');

      setState(() => status = 'fetching stream-url…');
      final urlResp =
          await dio.get('/api/library/native/stream-url/$itemId');
      final url = urlResp.data['url'] as String;
      log('stream-url OK: $url');

      setState(() => status = 'opening in media_kit…');
      await player.open(Media(url), play: true);
      log('player.open() returned, autoplay requested');
      setState(() => status = 'playing');
    } catch (e, st) {
      log('PLAYBACK FAILED: $e\n$st');
      setState(() => status = 'PLAYBACK ERROR: $e');
    }
  }

  Future<void> _joinAV() async {
    try {
      setState(() => roomState = 'reading token file…');
      final lines = await File('/tmp/wp-spike-livekit.txt').readAsLines();
      final wsUrl = lines[0].trim();
      final token = lines[1].trim();
      log('livekit url=$wsUrl');

      final r = lk.Room();
      room = r;
      r.createListener()
        ..on<lk.RoomConnectedEvent>((e) {
          log('LIVEKIT: RoomConnectedEvent');
          if (mounted) setState(() => roomState = 'connected');
        })
        ..on<lk.RoomDisconnectedEvent>((e) {
          log('LIVEKIT: RoomDisconnectedEvent reason=${e.reason}');
          if (mounted) setState(() => roomState = 'disconnected: ${e.reason}');
        })
        ..on<lk.LocalTrackPublishedEvent>((e) {
          log('LIVEKIT: LocalTrackPublished sid=${e.publication.sid} kind=${e.publication.kind}');
          _refreshTracks();
        })
        ..on<lk.TrackSubscribedEvent>((e) {
          log('LIVEKIT: TrackSubscribed sid=${e.publication.sid} participant=${e.participant.identity}');
          _refreshTracks();
        });

      setState(() => roomState = 'connecting…');
      await r.connect(wsUrl, token);
      log('LIVEKIT: connect() returned, state=${r.connectionState}');
      setState(() => roomState = 'connected (${r.connectionState})');

      try {
        await r.localParticipant?.setMicrophoneEnabled(true);
        log('LIVEKIT: microphone enabled');
      } catch (e) {
        log('LIVEKIT: mic enable failed: $e');
      }
      try {
        await r.localParticipant?.setCameraEnabled(true);
        log('LIVEKIT: camera enabled');
      } catch (e) {
        log('LIVEKIT: camera enable failed: $e');
        if (mounted) setState(() => roomState = 'connected, NO CAMERA: $e');
      }
      _refreshTracks();
    } catch (e, st) {
      log('LIVEKIT FAILED: $e\n$st');
      setState(() => roomState = 'ERROR: $e');
    }
  }

  void _refreshTracks() {
    final r = room;
    if (r == null) return;
    final tracks = <lk.VideoTrack>[];
    final lp = r.localParticipant;
    if (lp != null) {
      for (final pub in lp.videoTrackPublications) {
        final t = pub.track;
        if (t != null) tracks.add(t);
      }
    }
    for (final p in r.remoteParticipants.values) {
      for (final pub in p.videoTrackPublications) {
        final t = pub.track;
        if (t != null) tracks.add(t);
      }
    }
    if (mounted) {
      setState(() {
        videoTracks
          ..clear()
          ..addAll(tracks);
      });
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours}:$m:$s';
  }

  @override
  void dispose() {
    player.dispose();
    room?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: Video(controller: controller)),
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.all(8),
              color: Colors.black54,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('S1 status: $status',
                      style: const TextStyle(color: Colors.white)),
                  Text('pos ${_fmt(pos)} / dur ${_fmt(dur)}',
                      style: const TextStyle(
                          color: Colors.greenAccent,
                          fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 8),
                  Text('S2 room: $roomState',
                      style: const TextStyle(color: Colors.cyanAccent)),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: ElevatedButton(
              onPressed: _joinAV,
              child: const Text('Join A/V'),
            ),
          ),
          if (videoTracks.isNotEmpty)
            Positioned(
              bottom: 12,
              right: 12,
              child: Row(
                children: [
                  for (final t in videoTracks)
                    Container(
                      width: 200,
                      height: 150,
                      margin: const EdgeInsets.only(left: 8),
                      color: Colors.black,
                      child: lk.VideoTrackRenderer(t),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
