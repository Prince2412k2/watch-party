import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/update/desktop_updater.dart';

/// Checking for an update downloads it. Checking for an update must NOT install
/// it.
///
/// Applying an update quits and relaunches the app — mid-film, mid-party,
/// mid-anything. An earlier version of this feature had `check()` call
/// `install()` directly to save the user a second click, which meant pressing
/// "check for updates" could kill the running app. The whole point of the split
/// is that the download is free to happen on its own and the restart never is.
class _ReleaseApi extends MockApiClient {
  _ReleaseApi({required this.build, required this.bytes});

  final int build;
  final List<int> bytes;
  int downloads = 0;

  @override
  Future<Map<String, dynamic>> currentDesktopRelease() async => {
    'version': '9.9.9',
    'build': build,
    'commit': 'deadbee',
    'builtAt': '2026-08-09T00:00:00Z',
    'artifacts': {
      'linux': {
        'filename': 'watchparty.AppImage',
        'url': 'https://example.test/watchparty.AppImage',
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      },
      'windows': {
        'filename': 'watchparty.exe',
        'url': 'https://example.test/watchparty.exe',
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      },
      'macos': {
        'filename': 'watchparty.dmg',
        'url': 'https://example.test/watchparty.dmg',
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      },
    },
  };

  @override
  String get baseUrl => 'https://example.test';

  @override
  Future<void> downloadDesktopArtifact(
    String url,
    String destination, {
    void Function(int received, int total)? onProgress,
  }) async {
    downloads++;
    await File(destination).writeAsBytes(bytes);
    onProgress?.call(bytes.length, bytes.length);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final artifact = List<int>.generate(64, (i) => i);
  late Directory support;

  setUp(() {
    // path_provider has no implementation in a unit test, and the updater
    // stages its artifact in the app support directory. Point it at a temp dir
    // so the real download path runs end to end.
    support = Directory.systemTemp.createTempSync('update_support_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => support.path,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      support.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a found update downloads itself and then waits', () async {
    final api = _ReleaseApi(build: 999999, bytes: artifact);
    final controller = DesktopUpdateController(api);
    addTearDown(controller.dispose);

    await controller.check();

    // Downloaded and verified...
    expect(api.downloads, 1);
    expect(controller.state.status, UpdateStatus.readyToInstall);
    expect(controller.state.stagedPath, isNotNull);
    expect(controller.state.progress, 1);
    // ...and nothing was applied. If check() had installed, this process would
    // have been asked to quit.
    expect(File(controller.state.stagedPath!).existsSync(), isTrue);
    addTearDown(() {
      try {
        File(controller.state.stagedPath!).deleteSync();
      } catch (_) {}
    });
  });

  // NOTE: there is no "already up to date" case here. The installed build comes
  // from the bundled package metadata, which is not injectable and reads as 0 in
  // a unit test, so every release looks newer. That path is covered by
  // `isUpdateAvailable` in desktop_updater_test.dart.

  test('an insecure origin neither checks nor downloads', () async {
    final api = _InsecureApi(bytes: artifact);
    final controller = DesktopUpdateController(api);
    addTearDown(controller.dispose);

    await controller.check();

    expect(api.downloads, 0);
    expect(controller.state.status, UpdateStatus.error);
  });
}

class _InsecureApi extends _ReleaseApi {
  _InsecureApi({required super.bytes}) : super(build: 999999);

  @override
  String get baseUrl => 'http://updates.example.test';
}

