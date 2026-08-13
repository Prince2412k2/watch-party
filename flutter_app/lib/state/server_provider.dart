import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/config.dart';
import 'auth_provider.dart';
import 'providers.dart';

/// SharedPreferences key holding the runtime backend origin.
const kServerUrlPrefKey = 'server.baseUrl';

/// The origin a build falls back to when nothing has been chosen at runtime.
///
/// Non-null only for a build that baked one in (see [AppConfig.hasBakedServer]).
/// When it is non-null the app never asks for a server: there is always one, so
/// there is never a setup step to show.
String? get bakedServerUrl =>
    AppConfig.hasBakedServer ? AppConfig.apiBase : null;

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
  /// A change of origin drops the old origin's session first — see
  /// [_dropOriginSession].
  Future<void> setUrl(String raw) async {
    final url = normalize(raw);
    final originChanged = url != state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kServerUrlPrefKey, url);
    // Before repointing, so nothing can carry the previous origin's cookie into
    // the first request against the new one.
    if (originChanged) await _dropOriginSession();
    _ref.read(apiClientProvider).baseUrl = url;
    _ref.read(socketClientProvider).url = url;
    state = url;
  }

  /// Forget the runtime server (used by "change server", and by logout); the
  /// router then routes back to the setup screen.
  ///
  /// A build with an origin baked in falls back to THAT rather than to nothing:
  /// signing out of such a build must not strand the user on a server picker it
  /// does not show, which is what dropping to null did.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kServerUrlPrefKey);
    await _dropOriginSession();
    state = bakedServerUrl;
  }

  /// Discard the authentication state that belonged to the origin we are
  /// leaving: the persisted cookie jar plus the cached `Cookie:` header, and the
  /// signed-in user itself.
  ///
  /// Immediate rather than deferred to the next sign-in, because the jar
  /// survives the process: a session left behind here is a live credential that
  /// the app would replay against whichever backend it is pointed at next, and
  /// `authProvider` would meanwhile still claim a user the new origin has never
  /// seen.
  Future<void> _dropOriginSession() async {
    try {
      await _ref.read(apiClientProvider).clearSession();
    } catch (_) {
      // Best-effort: a jar that refuses to delete must not block the switch.
    }
    _ref.read(authProvider.notifier).markUnauthenticated();
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
