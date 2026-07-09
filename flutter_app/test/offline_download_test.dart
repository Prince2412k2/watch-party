import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/download/downloader.dart';
import 'package:watchparty/download/offline_manifest_store.dart';
import 'package:watchparty/models/models.dart';
import 'package:watchparty/state/offline_provider.dart';
import 'package:watchparty/state/providers.dart';

/// E8.2/E8.3 verification: a completed download surfaces in `offlineProvider`,
/// and `resolveOfflinePlayback` prefers its local path over a network stream
/// URL. Also confirms a title still mid-download (or never started) falls
/// back to the network URL — the branch [DownloadButton]/E4.2's player rely on.
///
/// Deliberately does NOT drive a real ~734MB download through
/// `background_downloader`: the package's `FileDownloader` talks to a native
/// platform channel that isn't wired up under plain `flutter test` (it hangs
/// waiting on `trackTasksInGroup`, not something a `cap/cancel` timeout can
/// paper over). Instead, [_FakeDownloader] overrides just the two seams
/// `OfflineNotifier` reads (`init`/`offlineRecords`/`offlineUpdates`), so the
/// real `OfflineNotifier` + `resolveOfflinePlayback` logic (E8.1/E8.3) runs
/// unmodified against a manifest as it would look right after a real
/// download completed.
void main() {
  test('a completed download surfaces in offlineProvider', () async {
    const itemId = 'title-42';
    final downloader = _FakeDownloader(offline: [
      OfflineRecord(
        itemId: itemId,
        title: 'Arrival',
        filePath: '/fake/downloads/$itemId.mkv',
        sizeBytes: 1024,
        runTimeTicks: 90 * 60 * 10000000,
        downloadedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [downloaderProvider.overrideWithValue(downloader)],
    );
    addTearDown(container.dispose);

    // offlineProvider rehydrates asynchronously on first read.
    final state = await _waitFor(
      () => container.read(offlineProvider),
      (records) => records.any((r) => r.itemId == itemId),
    );

    final record = state.firstWhere((r) => r.itemId == itemId);
    expect(record.title, 'Arrival');
    expect(record.filePath, '/fake/downloads/$itemId.mkv');
  });

  test('resolveOfflinePlayback prefers the local file once downloaded, falls back otherwise', () async {
    const itemId = 'title-7';
    const localPath = '/fake/local/path/title-7.mp4';
    final downloader = _FakeDownloader(offline: [
      OfflineRecord(
        itemId: itemId,
        title: 'Heat',
        filePath: localPath,
        downloadedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);

    final container = ProviderContainer(
      overrides: [downloaderProvider.overrideWithValue(downloader)],
    );
    addTearDown(container.dispose);

    await _waitFor(
      () => container.read(offlineProvider),
      (records) => records.any((r) => r.itemId == itemId),
    );

    final ref = container.read(_refProvider);
    const streamUrl = 'https://example.com/native/file?token=abc';

    final resolved = resolveOfflinePlayback(ref, itemId, streamUrl);
    expect(resolved.offline, isTrue);
    expect(resolved.url, localPath);

    // A title never downloaded (still in-flight or untouched) keeps using
    // the network URL — the fallback E4.2's player depends on.
    final untouched = resolveOfflinePlayback(ref, 'never-downloaded', streamUrl);
    expect(untouched.offline, isFalse);
    expect(untouched.url, streamUrl);
  });

  test('a live completion (offlineUpdates) flips offlineProvider without a restart', () async {
    const itemId = 'title-99';
    final downloader = _FakeDownloader(offline: const []);
    final container = ProviderContainer(
      overrides: [downloaderProvider.overrideWithValue(downloader)],
    );
    addTearDown(container.dispose);

    // Force rehydrate to run first (empty manifest).
    await _waitFor(() => container.read(offlineProvider), (r) => true);
    expect(container.read(offlineProvider).any((r) => r.itemId == itemId), isFalse);

    // Simulate `Downloader._onComplete` firing mid-session (a download that
    // finishes while the offline screen is already open).
    downloader.completeDownload(OfflineRecord(
      itemId: itemId,
      title: 'Klute',
      filePath: '/fake/klute.mkv',
      downloadedAt: DateTime.now().millisecondsSinceEpoch,
    ));

    final state = await _waitFor(
      () => container.read(offlineProvider),
      (records) => records.any((r) => r.itemId == itemId),
    );
    expect(state.firstWhere((r) => r.itemId == itemId).title, 'Klute');
  });
}

/// Overrides only the seams `OfflineNotifier` touches, so the test never
/// reaches `background_downloader`'s native platform channel.
class _FakeDownloader extends Downloader {
  _FakeDownloader({required List<OfflineRecord> offline})
      : _offline = offline,
        super(manifestStore: OfflineManifestStore(overrideDir: Directory.systemTemp));

  final List<OfflineRecord> _offline;
  final _updates = StreamController<OfflineRecord>.broadcast();

  void completeDownload(OfflineRecord record) => _updates.add(record);

  @override
  Future<void> init() async {}

  @override
  List<OfflineRecord> get offlineRecords => List.unmodifiable(_offline);

  @override
  Stream<OfflineRecord> get offlineUpdates => _updates.stream;
}

/// Fetches a real [Ref] out of the container — `resolveOfflinePlayback` wants
/// one (it only ever calls `ref.read`), and `ProviderContainer` itself isn't a `Ref`.
final _refProvider = Provider<Ref>((ref) => ref);

Future<T> _waitFor<T>(
  T Function() read,
  bool Function(T value) done, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final value = read();
    if (done(value)) return value;
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout (last value: $value)');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
