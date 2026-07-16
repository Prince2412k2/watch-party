import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/mock_api_client.dart';
import '../net/socket_client.dart';
import '../download/downloader.dart';
import '../cache/media_cache_proxy.dart';
import '../cache/cache_fill_controller.dart';

/// Core dependency-injection seams (PLAN §3.8). Phase 0 wires MOCK
/// implementations so the app boots and every epic has something to build
/// against. Epics swap in the real impls by overriding these providers at the
/// [ProviderScope] root (E2 → DioApiClient, E5 → IoSocketClient, …).

/// The API client. Overridden with a persistent [DioApiClient] once auth (E2)
/// is wired; defaults to an in-memory mock so the app runs with no backend.
final apiClientProvider = Provider<ApiClient>((ref) => MockApiClient());

/// The socket.io client for sync/chat. Mock by default.
final socketClientProvider =
    Provider<SocketClient>((ref) => MockSocketClient());

/// The resumable-download service (E8.1). A single [Downloader] instance is
/// shared by [downloadsProvider] and [offlineProvider]; both rehydrate from
/// its persisted state on first read.
final downloaderProvider = Provider<Downloader>((ref) => Downloader());

/// The on-device caching media proxy (Phase 2) playback routes network
/// streams through instead of a direct signed URL. `main.dart` builds the
/// real instance around the persistent [DioApiClient] and calls `start()`
/// before overriding this — the default here (built lazily off whatever
/// [apiClientProvider] resolves to, un-started) only exists so tests that
/// don't touch playback don't need to override it.
final mediaCacheProxyProvider = Provider<MediaCacheProxy>(
  (ref) => MediaCacheProxy(apiClient: ref.watch(apiClientProvider)),
);

/// The proactive whole-title cache-fill engine ("download = fill the
/// cache", Phase 3b) built off whatever [mediaCacheProxyProvider] resolves
/// to. Additive alongside the existing [downloaderProvider]-based
/// download/offline stack — nothing here is wired into that UI yet.
final cacheFillControllerProvider = Provider<CacheFillController>(
  (ref) => CacheFillController(proxy: ref.watch(mediaCacheProxyProvider)),
);
