import 'package:flutter/material.dart';

import '../ui/theme.dart';
import 'router.dart';

/// Root widget. Wires the frozen theme + router. State DI lives at the
/// [ProviderScope] in `main.dart`.
class WatchpartyApp extends StatefulWidget {
  const WatchpartyApp({super.key});

  @override
  State<WatchpartyApp> createState() => _WatchpartyAppState();
}

class _WatchpartyAppState extends State<WatchpartyApp> {
  final _router = buildRouter();

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
