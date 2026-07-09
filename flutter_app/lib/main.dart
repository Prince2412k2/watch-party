import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'app/config.dart';
import 'app/desktop_lifecycle.dart';
import 'data/api_client.dart';
import 'net/socket_client.dart';
import 'state/state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize libmpv (media_kit) once, before any player is created (E4 uses it).
  MediaKit.ensureInitialized();

  // E10 (packaging): window-state restore, tray icon, and close-to-tray on
  // desktop. Must run before the first frame; no-op on unsupported platforms.
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    await DesktopLifecycle.instance.init();
  }

  // The real, cookie-persisting API client (E2). Cookies live under the app's
  // support directory so a session survives a full app restart.
  final supportDir = await getApplicationSupportDirectory();
  final apiClient = await DioApiClient.persistent('${supportDir.path}/cookies');

  // The real socket.io client (E5). Its handshake needs the session cookie,
  // but dart:io sockets don't share dio's cookie jar and login happens well
  // after this point — so the cookie header is resolved lazily, from
  // [apiClient]'s jar, the moment something actually connects the socket.
  final socketClient = IoSocketClient(
    url: AppConfig.socketUrl,
    cookieHeaderProvider: () async {
      final cookies = await apiClient.cookieJar.loadForRequest(Uri.parse(AppConfig.apiBase));
      if (cookies.isEmpty) return null;
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    },
  );

  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(apiClient),
      socketClientProvider.overrideWithValue(socketClient),
    ],
  );

  // Restore a persisted session (GET /api/auth/me) before the first frame, so
  // the router never flashes `/login` for an already-authenticated user.
  await container.read(authProvider.notifier).restore();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const WatchpartyApp(),
    ),
  );
}
