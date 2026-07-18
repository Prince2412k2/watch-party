import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/update/desktop_updater.dart';

void main() {
  final json = <String, dynamic>{
    'version': '1.0.0-main.9',
    'build': 9,
    'commit': List.filled(40, 'a').join(),
    'builtAt': '2026-07-18T12:00:00Z',
    'artifacts': {
      'linux': {
        'filename': 'Watchparty.AppImage',
        'url': '/api/downloads/Watchparty.AppImage',
        'size': 3,
        'sha256': sha256.convert([1, 2, 3]).toString(),
      },
    },
  };

  test('uses the embedded monotonic build, not version text', () {
    final release = DesktopRelease.fromJson(json);
    expect(isUpdateAvailable(8, release), isTrue);
    expect(isUpdateAvailable(9, release), isFalse);
    expect(isUpdateAvailable(10, release), isFalse);
  });

  test('updates require HTTPS except loopback', () {
    expect(isSecureUpdateOrigin('https://watch.example.com'), isTrue);
    expect(isSecureUpdateOrigin('http://localhost:3000'), isTrue);
    expect(isSecureUpdateOrigin('http://127.0.0.1:3000'), isTrue);
    expect(isSecureUpdateOrigin('http://watch.example.com'), isFalse);
  });

  test('verifies both artifact size and SHA-256', () async {
    final dir = await Directory.systemTemp.createTemp('watchparty-update-test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/artifact')..writeAsBytesSync([1, 2, 3]);
    final artifact = DesktopRelease.fromJson(json).artifacts['linux']!;
    expect(await verifyArtifact(file, artifact), isTrue);
    file.writeAsBytesSync([1, 2, 4]);
    expect(await verifyArtifact(file, artifact), isFalse);
  });

  test('stores updates in an app-owned support directory', () async {
    final support = await Directory.systemTemp.createTemp(
      'watchparty-update-support',
    );
    addTearDown(() => support.delete(recursive: true));
    final artifact = DesktopRelease.fromJson(json).artifacts['linux']!;

    final file = await updateArtifactDestination(
      artifact,
      applicationSupportDirectory: support,
    );

    expect(
      file.path,
      '${support.path}${Platform.pathSeparator}updates'
      '${Platform.pathSeparator}Watchparty.AppImage',
    );
    expect(await file.parent.exists(), isTrue);
  });
}
