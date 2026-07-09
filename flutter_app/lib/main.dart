import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'data/api_client.dart';
import 'state/state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize libmpv (media_kit) once, before any player is created (E4 uses it).
  MediaKit.ensureInitialized();

  // The real, cookie-persisting API client (E2). Cookies live under the app's
  // support directory so a session survives a full app restart.
  final supportDir = await getApplicationSupportDirectory();
  final apiClient = await DioApiClient.persistent('${supportDir.path}/cookies');

  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(apiClient)],
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
