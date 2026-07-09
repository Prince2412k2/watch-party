import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme.dart';
import 'router.dart';

/// Root widget. Wires the frozen theme + router. State DI lives at the
/// [ProviderScope]/[UncontrolledProviderScope] in `main.dart`; by the time this
/// widget builds, boot-time session restore has already resolved, so the
/// router's auth redirect (E2) never flashes the wrong screen.
class WatchpartyApp extends ConsumerStatefulWidget {
  const WatchpartyApp({super.key});

  @override
  ConsumerState<WatchpartyApp> createState() => _WatchpartyAppState();
}

class _WatchpartyAppState extends ConsumerState<WatchpartyApp> {
  late final _router = buildRouter(ref);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Watchparty',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
