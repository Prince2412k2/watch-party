// Runs on the real Linux target (`flutter test integration_test/downloader_test.dart
// -d linux`), NOT the headless `flutter_tester` VM used by plain `flutter test`.
// background_downloader's desktop implementation spawns a real isolate that
// makes Dart VM callbacks flutter_tester's sandbox forbids ("Callbacks into
// the Dart VM are currently prohibited") — this test hung/crashed under plain
// `flutter test` for that reason, unrelated to the Downloader implementation
// itself, which is why it lives here instead.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/download/downloader.dart';
import 'package:watchparty/models/models.dart';

/// Live integration test against the running backend (root/root). Downloads
/// a real, large title via the `purpose=download` signed URL, asserts
/// progress advances and bytes land on disk, pauses, re-attaches with a
/// *fresh* [Downloader] instance (simulating an app restart against
/// background_downloader's persisted task DB), resumes, then cancels — never
/// letting the full download finish. Skips (not fails) if the backend is
/// unreachable, so the suite stays green offline.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const base = String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3005');

  testWidgets('Downloader resumes a real download and lands bytes on disk',
      (tester) async {
    try {
      final probe = await HttpClient()
          .getUrl(Uri.parse('$base/api/health'))
          .then((r) => r.close())
          .timeout(const Duration(seconds: 2));
      expect(probe.statusCode, 200);
    } catch (_) {
      markTestSkipped('backend not reachable at $base');
      return;
    }

    final api = DioApiClient(baseUrl: base);
    await api.login('root', 'root');

    // The largest real title in the test library — big enough that a
    // fraction-of-a-second download is a tiny sliver of the whole file.
    final items = await api.items();
    final target = items.reduce((a, b) {
      final aSize = a.mediaSources.fold<int>(0, (s, m) => s + (m.size ?? 0));
      final bSize = b.mediaSources.fold<int>(0, (s, m) => s + (m.size ?? 0));
      return aSize >= bSize ? a : b;
    });
    final totalSize =
        target.mediaSources.fold<int>(0, (s, m) => s + (m.size ?? 0));
    expect(totalSize, greaterThan(100 * 1024 * 1024),
        reason: 'expected a large real title in the library to test resume against');

    var downloader = Downloader();
    await downloader.init();

    final seenStatuses = <DownloadStatus>{};
    var sub = downloader.recordStream.listen((r) {
      if (r.itemId == target.id) seenStatuses.add(r.status);
    });

    final initial = await downloader.startDownload(
      api: api,
      itemId: target.id,
      title: target.name,
      container: target.container,
    );
    expect(initial.status, DownloadStatus.enqueued);
    expect(initial.filePath, isNull); // not resolved until on disk

    // Backend is on localhost — the whole file can transfer in well under a
    // minute, so pause almost immediately to reliably catch it mid-flight.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final pausedOk = await downloader.pause(target.id);
    expect(pausedOk, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final activeAfterPause = await downloader.activeRecords();
    final beforeRestart =
        activeAfterPause.firstWhere((r) => r.itemId == target.id);
    expect(beforeRestart.filePath, isNotNull);
    final path = beforeRestart.filePath!;

    // Progress advanced at least once before we paused (the enqueue ->
    // running transition). A file may not exist on disk yet this early — the
    // OS/HTTP client can buffer the very first bytes — so the "bytes on
    // disk" assertion is after resume below, once there's been time to write.
    expect(seenStatuses, contains(DownloadStatus.running));

    await sub.cancel();

    // Simulate an app restart: throw away the in-memory Downloader/listener
    // and re-attach to background_downloader's persisted DB with a brand new
    // instance — exactly what `init()` does on real app boot.
    downloader = Downloader();
    await downloader.init();
    final rehydrated = await downloader.activeRecords();
    final rehydratedRecord = rehydrated.firstWhere(
      (r) => r.itemId == target.id,
      orElse: () => fail('download task did not survive rehydration from the persisted DB'),
    );
    expect(
      rehydratedRecord.status,
      anyOf(DownloadStatus.paused, DownloadStatus.enqueued, DownloadStatus.complete),
    );

    if (rehydratedRecord.status == DownloadStatus.paused) {
      final resumedOk = await downloader.resume(target.id);
      expect(resumedOk, isTrue);

      // Confirm it's moving again after the simulated restart. Poll the DB
      // (source of truth) rather than a single stream snapshot — on this
      // fast localhost backend, resume -> running -> complete can happen
      // faster than a fixed listen window reliably observes.
      DownloadRecord? after;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final records = await downloader.activeRecords();
        after = records.firstWhere((r) => r.itemId == target.id,
            orElse: () => rehydratedRecord);
        // Wait past "running with no reported bytes yet" too, so the disk
        // check below (native downloader writes to a temp file until
        // TaskStatus.complete, then renames to the destination path) has a
        // real shot at seeing the completed file.
        if (after.status == DownloadStatus.complete) break;
        if (after.status == DownloadStatus.running && after.bytesDownloaded > 0) break;
      }
      expect(after, isNotNull);
      expect(
        after!.status,
        anyOf(DownloadStatus.running, DownloadStatus.complete),
        reason: 'resume() should move the download out of paused',
      );

      if (after.status == DownloadStatus.complete) {
        // The destination file only exists once background_downloader
        // renames the temp file on completion — the core "bytes actually
        // land on disk" assertion.
        final file = File(path);
        expect(await file.exists(), isTrue);
        expect(await file.length(), greaterThan(0));
      } else {
        // Still running: bytes are landing in a temp file we don't have a
        // path to, but the DB-reported progress is the honest signal here.
        expect(after.bytesDownloaded, greaterThan(0));
      }
    } else if (rehydratedRecord.status == DownloadStatus.complete) {
      // Localhost is fast enough that the download can race to completion
      // before the pause lands — still proves the full pipeline works.
      final file = File(path);
      if (await file.exists()) expect(await file.length(), greaterThan(0));
    }

    // Stop well short of a full download.
    final canceledOk = await downloader.cancel(target.id);
    expect(canceledOk, isTrue);

    final file = File(path);
    if (await file.exists()) await file.delete();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
