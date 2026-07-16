import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'app/desktop_lifecycle.dart';
import 'cache/media_cache_proxy.dart';
import 'data/api_client.dart';
import 'net/socket_client.dart';
import 'state/state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Debug-only: expose the running app to an AI agent (screenshots + input)
  // over an MCP server. Gated behind kDebugMode so it never ships in release,
  // AND behind WP_SKILL=1 so a normal dev run doesn't load it (it hooks the
  // render pipeline; opt in only when driving the app with an agent).
  if (kDebugMode && Platform.environment['WP_SKILL'] == '1') {
    FlutterSkillBinding.ensureInitialized();
  }
  // Initialize libmpv (media_kit) once, before any player is created (E4 uses it).
  MediaKit.ensureInitialized();

  // E10 (packaging): window-state restore, tray icon, and close-to-tray on
  // desktop. Must run before the first frame; no-op on unsupported platforms.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await DesktopLifecycle.instance.init();
  }

  // Backend-agnostic: the origin is chosen at runtime (the user pastes a
  // server URL) and persisted in SharedPreferences. Read it before building
  // the clients so they start pointed at the right server; null means "not
  // configured yet" and the router routes to the setup screen.
  final prefs = await SharedPreferences.getInstance();
  final savedServerUrl = prefs.getString(kServerUrlPrefKey);

  // The real, cookie-persisting API client (E2). Cookies live under the app's
  // support directory so a session survives a full app restart.
  final supportDir = await getApplicationSupportDirectory();
  final apiClient = await DioApiClient.persistent(
    '${supportDir.path}/cookies',
    baseUrl: savedServerUrl, // null → DioApiClient falls back to its default
  );

  // The real socket.io client (E5). Its handshake needs the session cookie,
  // but dart:io sockets don't share dio's cookie jar and login happens well
  // after this point — so the cookie header is resolved lazily, from
  // [apiClient]'s jar, the moment something actually connects the socket.
  final socketClient = IoSocketClient(
    url: savedServerUrl ?? AppConfig.socketUrl,
    cookieHeaderProvider: () async {
      // Load the session cookie for the CURRENT (runtime-configured) origin,
      // not the compile-time default — otherwise, once the user points at a
      // different backend, the socket handshake carries no cookie and the
      // server rejects party/sync actions as unauthenticated.
      final cookies = await apiClient.cookieJar.loadForRequest(
        Uri.parse(apiClient.baseUrl),
      );
      if (cookies.isEmpty) return null;
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    },
  );

  // The on-device caching media proxy (Phase 2): mints/re-mints signed
  // stream URLs off [apiClient] itself, so it must be built after it. Started
  // before the container exists so `mediaCacheProxyProvider.urlFor` is usable
  // the moment any screen reads it — no screen awaits proxy startup itself.
  final mediaCacheProxy = MediaCacheProxy(apiClient: apiClient);
  await mediaCacheProxy.start();
  // Bound the on-device cache (size cap + 30-day LRU, Phase 3a) once at
  // boot. Nothing is open/playing yet at this point, so there's nothing to
  // protect; a small, one-shot scan-and-delete, not worth blocking on in the
  // background but also cheap enough not to bother deferring.
  await mediaCacheProxy.evict();

  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      socketClientProvider.overrideWithValue(socketClient),
      mediaCacheProxyProvider.overrideWithValue(mediaCacheProxy),
      serverConfigProvider.overrideWith(
        (ref) => ServerConfigNotifier(ref, savedServerUrl),
      ),
    ],
  );

  // Pause playback when the window hides to the tray: close-to-tray keeps the
  // process (and libmpv) alive, so without this, audio keeps playing from a
  // window the user thinks they closed.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    DesktopLifecycle.instance.onBeforeHide = () {
      container.read(playerControllerProvider).pause();
    };
  }

  // Restore a persisted session (GET /api/auth/me) before the first frame, so
  // the router never flashes `/login` for an already-authenticated user. Only
  // meaningful once a server is configured; otherwise the router sends the
  // user to the setup screen first.
  if ((savedServerUrl ?? '').isNotEmpty) {
    await container.read(authProvider.notifier).restore();
  } else {
    // No server chosen yet — show login (with the server picker) immediately.
    container.read(authProvider.notifier).markUnauthenticated();
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WatchpartyApp(),
    ),
  );
}
