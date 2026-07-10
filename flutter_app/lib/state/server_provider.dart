import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers.dart';

/// SharedPreferences key holding the runtime backend origin.
const kServerUrlPrefKey = 'server.baseUrl';

/// The backend the app is currently pointed at (null/empty until the user
/// connects to one). Made runtime-settable so the app is backend-agnostic —
/// the user pastes a server URL instead of it being baked in at build time.
///
/// The initial value is injected at boot from SharedPreferences (see
/// `main.dart`'s override); [setUrl]/[clear] both persist and push the change
/// onto the live [ApiClient] + [SocketClient] so every request follows.
class ServerConfigNotifier extends StateNotifier<String?> {
  ServerConfigNotifier(this._ref, String? initial) : super(initial);

  final Ref _ref;

  /// True once a server has been chosen.
  bool get isConfigured => (state ?? '').isNotEmpty;

  /// Normalize [raw], persist it, and repoint the API + socket clients at it.
  Future<void> setUrl(String raw) async {
    final url = normalize(raw);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kServerUrlPrefKey, url);
    _ref.read(apiClientProvider).baseUrl = url;
    _ref.read(socketClientProvider).url = url;
    state = url;
  }

  /// Forget the current server (used by "change server"); the router then
  /// routes back to the setup screen.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kServerUrlPrefKey);
    state = null;
  }

  /// Trim, default the scheme to https, and strip any trailing slash so
  /// `example.ts.net/` and `https://example.ts.net` normalize identically.
  static String normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'https://$s';
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}

final serverConfigProvider =
    StateNotifierProvider<ServerConfigNotifier, String?>(
  (ref) => ServerConfigNotifier(ref, null),
);
