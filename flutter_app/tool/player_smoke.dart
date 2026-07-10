// Standalone windowed smoke test for E4.1 MediaKitPlayerController.
//
// Not part of the shipped app — a verification harness. It builds a minimal
// Flutter window (so libmpv has a real render surface), resolves a live signed
// native stream-url, drives the real MediaKitPlayerController + VideoView, and
// appends position/track/error samples to a log file for headless inspection.
//
// Run:  flutter run -d linux -t tool/player_smoke.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'package:watchparty/player/media_kit_player_controller.dart';
import 'package:watchparty/player/video_view.dart';

const _backend = 'http://localhost:3005';
const _itemId = '19e55dfac3a265dff5ee14af05dd0a4c';
final _log = File('/tmp/wp-player-smoke.log');

void _w(String m) {
  final line = '[SMOKE] ${DateTime.now().toIso8601String()} $m';
  // ignore: avoid_print
  print(line);
  try {
    _log.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  try {
    _log.writeAsStringSync('', flush: true);
  } catch (_) {}
  _w('smoke start');
  runApp(const MaterialApp(home: _Smoke()));
}

class _Smoke extends StatefulWidget {
  const _Smoke();
  @override
  State<_Smoke> createState() => _SmokeState();
}

class _SmokeState extends State<_Smoke> {
  final controller = MediaKitPlayerController();
  String status = 'starting';

  @override
  void initState() {
    super.initState();
    controller.position.listen((p) => _w('position=${p.inMilliseconds}ms'));
    controller.buffering.listen((b) => _w('buffering=$b'));
    controller.playing.listen((p) => _w('playing=$p'));
    controller.duration.listen((d) => _w('duration=${d.inMilliseconds}ms'));
    controller.errors.listen((e) => _w('ERROR=$e'));
    controller.tracks.listen((t) => _w(
        'tracks audio=${t.audio.map((a) => "${a.id}:${a.language}").toList()} '
        'subtitle=${t.subtitle.map((s) => "${s.id}:${s.language}").toList()}'));
    _go();
  }

  Future<void> _go() async {
    try {
      final dio = Dio(BaseOptions(baseUrl: _backend));
      final cookies = <String>[];
      final login = await dio.post<Map<String, dynamic>>('/api/auth/login',
          data: {'username': 'root', 'password': 'root'});
      final sc = login.headers.map['set-cookie'];
      if (sc != null) cookies.addAll(sc.map((c) => c.split(';').first));
      _w('login ok');
      final r = await dio.get<Map<String, dynamic>>(
          '/api/library/native/stream-url/$_itemId',
          options: Options(headers: {'cookie': cookies.join('; ')}));
      final url = r.data!['url'] as String;
      _w('stream-url ok: $url');
      await controller.open(url, autoplay: true);
      _w('open() returned');
      setState(() => status = 'playing');
    } catch (e, st) {
      _w('FAILED: $e\n$st');
      setState(() => status = 'ERROR: $e');
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: VideoView(controller: controller)),
        Positioned(top: 8, left: 8, child: Text(status)),
      ]),
    );
  }
}
