/// App-wide configuration. The backend base URL defaults to the local dev
/// server and is overridable at build/run time:
///
///   flutter run --dart-define=API_BASE=https://host.tail0a3558.ts.net
class AppConfig {
  const AppConfig._();

  /// Backend origin (Express `/api`, socket.io, native stream proxy).
  ///
  /// This is the ONLY origin the app ever needs. Jellyfin is never named on the
  /// client: the server proxies it origin-relative at `/jellyfin`, streams its
  /// files through `/api/library/native/file`, and holds `JELLYFIN_URL` in its
  /// own environment. So a build that knows this knows everything.
  static const String apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3005');

  /// Whether [apiBase] was baked in at build time
  /// (`--dart-define=API_BASE=https://…`) rather than defaulted to localhost.
  ///
  /// A build that names its backend is a build for one deployment, and its
  /// users should never be shown a server field — there is nothing for them to
  /// answer. So this switches the whole "which server?" affordance off: no
  /// setup step, no chip on the login page, no row in settings.
  ///
  /// Without the define, everything behaves as it always has — the app stays
  /// backend-agnostic for development and for anyone building it themselves.
  static const bool hasBakedServer = bool.hasEnvironment('API_BASE');

  /// socket.io connects to the same origin as the API.
  static String get socketUrl => apiBase;

  /// Convenience: build an absolute `/api/...` URL.
  static String api(String path) =>
      '$apiBase${path.startsWith('/') ? '' : '/'}$path';
}
