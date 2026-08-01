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


  group('macOS self-update', () {
    test('macAppBundlePath finds the bundle from the executable inside it', () {
      expect(
        macAppBundlePath('/Applications/Watchparty.app/Contents/MacOS/Watchparty'),
        '/Applications/Watchparty.app',
      );
    });

    test('macAppBundlePath returns null for anything that is not a bundle', () {
      // A bare `flutter run` binary, or an unexpected layout: better to fall back
      // to a manual install than delete the wrong directory.
      for (final path in <String>[
        '/home/p/build/linux/x64/release/bundle/watchparty',
        '/Applications/Watchparty.app/Contents/Frameworks/x',
        '/usr/local/bin/watchparty',
        'watchparty',
        '',
      ]) {
        expect(macAppBundlePath(path), isNull, reason: path);
      }
    });

    test('macSwapScript waits for the pid, then replaces and relaunches', () {
      final script = macSwapScript(
        pid: 4242,
        stagedApp: '/tmp/updates/Watchparty-new.app',
        installedApp: '/Applications/Watchparty.app',
      );
      // Order is the whole correctness argument: nothing may touch the installed
      // bundle until this process is gone.
      final waitAt = script.indexOf('kill -0 4242');
      final removeAt = script.indexOf('rm -rf');
      final dittoAt = script.indexOf('ditto');
      final openAt = script.indexOf('open');
      expect(waitAt, greaterThan(-1));
      expect(waitAt, lessThan(removeAt));
      expect(removeAt, lessThan(dittoAt));
      expect(dittoAt, lessThan(openAt));
      expect(script, contains("'/Applications/Watchparty.app'"));
      expect(script, contains('xattr -dr com.apple.quarantine'));
    });
  });
}
