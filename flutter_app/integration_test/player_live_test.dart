// Live playback integration test for E4.1 MediaKitPlayerController.
//
// Requires the backend running at http://localhost:3005 (login root/root) and a
// Linux desktop device. Opens the real signed native stream-url for a known
// item, plays it through the media_kit-backed controller, and asserts the
// position stream advances (i.e. libmpv is decoding the direct-play file).
//
// Run:  flutter test integration_test/player_live_test.dart -d linux
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:watchparty/player/media_kit_player_controller.dart';

const _backend = 'http://localhost:3005';
const _itemId = '19e55dfac3a265dff5ee14af05dd0a4c';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('opens a live native stream-url and position advances',
      (tester) async {
    // 1. Resolve a real signed stream-url (URL resolution is the caller's job,
    //    per the contract — done here in the test harness, not the controller).
    final dio = Dio(BaseOptions(baseUrl: _backend));
    final cookies = <String>[];
    final login = await dio.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'username': 'root', 'password': 'root'},
    );
    final setCookie = login.headers.map['set-cookie'];
    if (setCookie != null) {
      cookies.addAll(setCookie.map((c) => c.split(';').first));
    }
    final urlResp = await dio.get<Map<String, dynamic>>(
      '/api/library/native/stream-url/$_itemId',
      options: Options(headers: {'cookie': cookies.join('; ')}),
    );
    final url = urlResp.data!['url'] as String;
    expect(url, isNotEmpty);

    // 2. Drive the controller under test.
    final controller = MediaKitPlayerController();
    final positions = <Duration>[];
    final sub = controller.position.listen(positions.add);

    await controller.open(url, autoplay: true);

    // 3. Pump-and-wait up to ~20s for the position to cross 500ms.
    var advanced = false;
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (controller.positionNow > const Duration(milliseconds: 500)) {
        advanced = true;
        break;
      }
    }

    expect(controller.lastError, isNull,
        reason: 'player reported error: ${controller.lastError}');
    expect(advanced, isTrue,
        reason: 'position never advanced past 500ms; '
            'last=${controller.positionNow}, samples=${positions.length}');
    expect(controller.durationNow, greaterThan(Duration.zero),
        reason: 'duration was never reported');

    await sub.cancel();
    await controller.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
