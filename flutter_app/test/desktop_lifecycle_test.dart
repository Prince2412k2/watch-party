import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:watchparty/app/desktop_lifecycle.dart';

/// One race per test. `onWindowMoved`/`onWindowResized` arrive once per frame
/// of a drag, so everything here is about what happens when the geometry
/// changes faster than it can be stored.
void main() {
  test('restored bounds must leave a usable area on a current display', () {
    const display = Rect.fromLTWH(0, 0, 1920, 1080);

    expect(
      windowBoundsAreVisible(const Rect.fromLTWH(1800, 100, 400, 400), const [
        display,
      ]),
      isTrue,
    );
    expect(
      windowBoundsAreVisible(const Rect.fromLTWH(2000, 100, 400, 400), const [
        display,
      ]),
      isFalse,
    );
  });

  test('restored size is clamped to the current display', () {
    expect(
      clampWindowSize(const Size(3000, 2000), const Size(1920, 1080)),
      const Size(1920, 1080),
    );
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  const someBounds = Rect.fromLTWH(120, 80, 1400, 900);
  const debounce = Duration(milliseconds: 400);

  WindowGeometryRecorder recorderThat({
    required Future<WindowGeometry> Function() read,
    required Future<void> Function(WindowGeometry) write,
    Duration wait = debounce,
  }) => WindowGeometryRecorder(read: read, write: write, debounce: wait);

  group('window geometry writes', () {
    test('a drag of many callbacks collapses into one write', () {
      fakeAsync((fa) {
        var writes = 0;
        final recorder = recorderThat(
          read: () async =>
              WindowGeometry.from(bounds: someBounds, maximized: false),
          write: (_) async => writes++,
        );

        // 40 frames of dragging, none of them 400ms apart.
        for (var frame = 0; frame < 40; frame++) {
          recorder.schedule();
          fa.elapse(const Duration(milliseconds: 16));
        }
        expect(writes, 0, reason: 'nothing should be written mid-gesture');
        expect(recorder.hasPendingWrite, isTrue);

        fa.elapse(debounce);
        fa.flushMicrotasks();
        expect(writes, 1);
        expect(recorder.hasPendingWrite, isFalse);
      });
    });

    test('a read and its write are never split by another round', () async {
      final log = <String>[];
      var reads = 0;
      final recorder = recorderThat(
        wait: Duration.zero,
        read: () async {
          final n = reads++;
          log.add('read $n');
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return WindowGeometry.from(
            bounds: Rect.fromLTWH(n.toDouble(), 0, 1400, 900),
            maximized: false,
          );
        },
        write: (geometry) async {
          log.add('write ${geometry.normalBounds!.left.toInt()}');
          await Future<void>.delayed(const Duration(milliseconds: 5));
        },
      );

      // Three rounds fired without awaiting each other — what a burst of
      // move/resize callbacks used to do straight to SharedPreferences.
      await Future.wait([recorder.flush(), recorder.flush(), recorder.flush()]);

      expect(log, [
        'read 0',
        'write 0',
        'read 1',
        'write 1',
        'read 2',
        'write 2',
      ]);
    });

    test(
      'closing mid-drag writes the pending geometry instead of losing it',
      () async {
        var writes = 0;
        WindowGeometry? stored;
        final recorder = recorderThat(
          // Long enough that the timer would never fire before `exit(0)`.
          wait: const Duration(seconds: 30),
          read: () async =>
              WindowGeometry.from(bounds: someBounds, maximized: false),
          write: (geometry) async {
            writes++;
            stored = geometry;
          },
        );

        recorder.schedule();
        expect(recorder.hasPendingWrite, isTrue);

        // What _shutdown() awaits.
        await recorder.flush();

        expect(writes, 1);
        expect(recorder.hasPendingWrite, isFalse);
        expect(stored!.normalBounds, someBounds);
      },
    );

    test('a write that throws neither escapes nor wedges the queue', () async {
      var writes = 0;
      final recorder = recorderThat(
        wait: Duration.zero,
        read: () async =>
            WindowGeometry.from(bounds: someBounds, maximized: false),
        write: (_) async {
          writes++;
          if (writes == 1) throw StateError('preferences unavailable');
        },
      );

      await recorder.flush();
      await recorder.flush();

      expect(writes, 2, reason: 'the second write must still get its turn');
    });
  });

  group('maximized windows', () {
    test(
      'report no normal bounds, because the live ones are the maximized frame',
      () {
        final maximized = WindowGeometry.from(
          bounds: const Rect.fromLTWH(0, 0, 3840, 2160),
          maximized: true,
        );
        expect(maximized.normalBounds, isNull);
        expect(maximized.maximized, isTrue);

        final restored = WindowGeometry.from(
          bounds: someBounds,
          maximized: false,
        );
        expect(restored.normalBounds, someBounds);
        expect(restored.maximized, isFalse);
      },
    );

    test(
      'keep the size and position the window will unmaximize back to',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final prefs = await SharedPreferences.getInstance();

        await persistWindowGeometry(
          prefs,
          WindowGeometry.from(bounds: someBounds, maximized: false),
        );
        // Then the user maximizes: the frame is now the whole screen.
        await persistWindowGeometry(
          prefs,
          WindowGeometry.from(
            bounds: const Rect.fromLTWH(0, 0, 3840, 2160),
            maximized: true,
          ),
        );

        // The stored geometry is still the window, not the screen. Writing the
        // maximized frame here is what used to make an unmaximize (or the next
        // launch) come up at 3840x2160 with the real window size gone.
        expect(prefs.getDouble(kWindowXPref), 120);
        expect(prefs.getDouble(kWindowYPref), 80);
        expect(prefs.getDouble(kWindowWPref), 1400);
        expect(prefs.getDouble(kWindowHPref), 900);
        expect(prefs.getBool(kWindowMaximizedPref), isTrue);
      },
    );

    test(
      'the persisted keys are the schema the installed base already has',
      () {
        // A rename silently loses everyone's window position, so it is pinned.
        expect(kWindowXPref, 'desktop.window.x');
        expect(kWindowYPref, 'desktop.window.y');
        expect(kWindowWPref, 'desktop.window.w');
        expect(kWindowHPref, 'desktop.window.h');
        expect(kWindowMaximizedPref, 'desktop.window.maximized');
      },
    );
  });
}
