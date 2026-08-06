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

    test('isRunnableMacBundle only accepts a bundle with an executable', () async {
      final root = await Directory.systemTemp.createTemp('watchparty-bundle');
      addTearDown(() => root.delete(recursive: true));

      final hollow = '${root.path}/Hollow.app';
      await Directory('$hollow/Contents/MacOS').create(recursive: true);
      expect(await isRunnableMacBundle(hollow), isFalse);

      final headless = '${root.path}/Headless.app';
      await Directory('$headless/Contents').create(recursive: true);
      expect(await isRunnableMacBundle(headless), isFalse);

      final good = '${root.path}/Good.app';
      await File('$good/Contents/MacOS/Good').create(recursive: true);
      expect(await isRunnableMacBundle(good), isTrue);
    });

    test('shellQuote survives a quote or a space in the install path', () {
      expect(
        shellQuote('/Applications/Watchparty.app'),
        "'/Applications/Watchparty.app'",
      );
      // The apostrophe closes the quoted word, escapes itself, and reopens it —
      // otherwise the rest of the path is handed to `sh` as commands.
      expect(
        shellQuote("/Users/bo'b/Watchparty.app"),
        r"'/Users/bo'\''b/Watchparty.app'",
      );
      expect(
        shellQuote('/Volumes/My Disk/Watchparty.app'),
        "'/Volumes/My Disk/Watchparty.app'",
      );
    });

    test('macSwapScript never removes the install before the replacement lands', () {
      const installed = '/Applications/Watchparty.app';
      final script = macSwapScript(
        pid: 4242,
        stagedApp: '/tmp/updates/Watchparty-new.app',
        installedApp: installed,
      );

      final waitAt = script.indexOf('kill -0 4242');
      final moveAsideAt = script.indexOf("/bin/mv '$installed'");
      final dittoAt = script.indexOf('/usr/bin/ditto');
      final removeInstalledAt = script.indexOf("/bin/rm -rf '$installed'");
      final restoreAt = script.indexOf("/bin/mv '${macRollbackPath(installed)}'");

      expect(waitAt, greaterThan(-1));
      // Nothing may touch the bundle until this process is gone…
      expect(waitAt, lessThan(moveAsideAt));
      // …the working copy is moved aside, not deleted, before ditto runs…
      expect(moveAsideAt, lessThan(dittoAt));
      // …and the only deletion of the install is in the rollback branch after
      // ditto, immediately before the old bundle is moved back.
      expect(removeInstalledAt, greaterThan(dittoAt));
      expect(removeInstalledAt, lessThan(restoreAt));
      expect(script, contains('xattr'));
      // `set -e` would abort the script mid-swap, which is the state that left
      // a user with no app at all.
      expect(script, isNot(contains('set -e')));
    });

    // These run the REAL script under /bin/sh with stand-ins for the macOS-only
    // tools, so the rollback is proven by executing it rather than by reading
    // it. That is the only way to be sure a failed replacement leaves a
    // launchable app behind.
    group('swap script, executed', () {
      late Directory root;
      late Directory bin;
      late File openLog;
      late String installed;
      late String staged;

      setUp(() async {
        root = await Directory.systemTemp.createTemp('watchparty-swap');
        bin = await Directory('${root.path}/bin').create();
        openLog = File('${root.path}/open.log');
        installed = '${root.path}/Watchparty.app';
        staged = '${root.path}/updates/Watchparty-new.app';
      });

      tearDown(() => root.delete(recursive: true));

      Future<String> stub(String name, String body) async {
        final file = File('${bin.path}/$name');
        await file.writeAsString('#!/bin/sh\n$body\n');
        await Process.run('/bin/chmod', ['+x', file.path]);
        return file.path;
      }

      Future<void> writeBundle(String path, String marker) async {
        final executable = File('$path/Contents/MacOS/Watchparty');
        await executable.create(recursive: true);
        await executable.writeAsString(marker);
      }

      String? markerAt(String bundle) {
        final executable = File('$bundle/Contents/MacOS/Watchparty');
        return executable.existsSync() ? executable.readAsStringSync() : null;
      }

      Future<MacUpdateTools> tools({required bool dittoWorks}) async =>
          MacUpdateTools(
            // Real ditto copies the SOURCE'S CONTENTS into a fresh destination.
            ditto: await stub(
              'ditto',
              dittoWorks ? r'mkdir -p "$2" && cp -R "$1/." "$2"' : 'exit 1',
            ),
            xattr: await stub('xattr', 'exit 0'),
            open: await stub('open', "printf '%s\\n' \"\$1\" >> '${openLog.path}'"),
          );

      Future<ProcessResult> runSwap(MacUpdateTools stubs) async {
        // A reaped pid: `kill -0` on it fails immediately, so the script's wait
        // loop falls straight through instead of the test hanging on it.
        final gone = await Process.start('/bin/sh', const ['-c', 'exit 0']);
        final gonePid = gone.pid;
        await gone.exitCode;

        final script = File('${root.path}/swap.sh');
        await script.writeAsString(macSwapScript(
          pid: gonePid,
          stagedApp: staged,
          installedApp: installed,
          tools: stubs,
        ));
        // Timed out rather than left to hang: the script's first act is a wait
        // loop, and a test that never returns is worse than a failing one.
        return Process.run(
          '/bin/sh',
          [script.path],
        ).timeout(const Duration(seconds: 20));
      }

      test('swaps in the new app and cleans up after itself', () async {
        await writeBundle(installed, 'OLD');
        await writeBundle(staged, 'NEW');

        final result = await runSwap(await tools(dittoWorks: true));

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(markerAt(installed), 'NEW');
        expect(Directory(macRollbackPath(installed)).existsSync(), isFalse);
        expect(Directory(staged).existsSync(), isFalse);
        expect(openLog.readAsStringSync().trim(), installed);
      });

      test('restores the working install when the replacement fails', () async {
        await writeBundle(installed, 'OLD');
        await writeBundle(staged, 'NEW');

        final result = await runSwap(await tools(dittoWorks: false));

        expect(result.exitCode, 1);
        // The whole point: the user is left with a launchable app, and it is
        // relaunched for them.
        expect(markerAt(installed), 'OLD');
        expect(Directory(macRollbackPath(installed)).existsSync(), isFalse);
        expect(openLog.readAsStringSync().trim(), installed);
        // Kept, so a retry does not need to download the DMG again.
        expect(Directory(staged).existsSync(), isTrue);
      });

      test('touches nothing when the install cannot be moved aside', () async {
        // No installed bundle at all, so the `mv` fails. This is the branch that
        // must not go on to delete or copy anything.
        await writeBundle(staged, 'NEW');

        final result = await runSwap(await tools(dittoWorks: true));

        expect(result.exitCode, 1);
        expect(Directory(installed).existsSync(), isFalse);
        expect(Directory(macRollbackPath(installed)).existsSync(), isFalse);
        expect(Directory(staged).existsSync(), isTrue);
      });

      test('swaps through an install path with a quote and a space', () async {
        installed = "${root.path}/Bo'b's Watch party.app";
        await writeBundle(installed, 'OLD');
        await writeBundle(staged, 'NEW');

        final result = await runSwap(await tools(dittoWorks: true));

        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(markerAt(installed), 'NEW');
        expect(openLog.readAsStringSync().trim(), installed);
      });
    }, skip: Platform.isWindows ? 'needs a POSIX shell' : null);
  });
}
