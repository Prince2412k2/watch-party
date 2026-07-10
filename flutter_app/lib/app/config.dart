/// App-wide configuration. The backend base URL defaults to the local dev
/// server and is overridable at build/run time:
///
///   flutter run --dart-define=API_BASE=https://host.tail0a3558.ts.net
class AppConfig {
  const AppConfig._();

  /// Backend origin (Express `/api`, socket.io, native stream proxy).
  static const String apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:3005');

  /// socket.io connects to the same origin as the API.
  static String get socketUrl => apiBase;

  /// Convenience: build an absolute `/api/...` URL.
  static String api(String path) =>
      '$apiBase${path.startsWith('/') ? '' : '/'}$path';
}
