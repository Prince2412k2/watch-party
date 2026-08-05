/// The shared browser, as the server describes it on `party:state`.
///
/// Hand-written rather than freezed on purpose: it is a leaf value object with a
/// single `fromJson`, and keeping it out of the generated models means this
/// feature does not require a `build_runner` pass to build.
library;

class SharedBrowserRequest {
  const SharedBrowserRequest({required this.userId, required this.name});

  final String userId;
  final String name;
}

class SharedBrowserState {
  const SharedBrowserState({
    required this.state,
    this.url,
    this.driverUserId,
    this.requests = const [],
    this.error,
    this.screenWidth,
    this.screenHeight,
  });

  /// 'starting' — the container accepted the request but no frames yet.
  /// 'active'   — the stream is live.
  /// 'error'    — it failed; [error] says how.
  final String state;
  final String? url;

  /// The one participant whose input reaches the remote browser.
  final String? driverUserId;
  final List<SharedBrowserRequest> requests;
  final String? error;

  /// The remote screen's pixel size, as reported by the server. Needed to
  /// translate a click in this app's window into a coordinate on that screen —
  /// the renderer will not tell us.
  ///
  /// Null only when talking to a server older than this field. Control is NOT
  /// gated on it: gating meant a version skew disabled driving with no
  /// explanation, which is a worse failure than coordinates being off on a
  /// non-default screen size. See [remoteWidth].
  final int? screenWidth;
  final int? screenHeight;

  bool get starting => state == 'starting';
  bool get active => state == 'active';
  bool get failed => state == 'error';

  /// The container's default geometry, and the fallback when the server does not
  /// say. Matches BROWSER_SCREEN_W/H's defaults in compose.
  static const int defaultWidth = 1280;
  static const int defaultHeight = 720;

  int get remoteWidth => screenWidth ?? defaultWidth;
  int get remoteHeight => screenHeight ?? defaultHeight;

  static SharedBrowserState? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);
    final state = map['state']?.toString();
    if (state == null) return null;
    final requests = (map['requests'] as List?) ?? const [];
    final screen = map['screen'];
    return SharedBrowserState(
      state: state,
      url: map['url']?.toString(),
      driverUserId: map['driverUserId']?.toString(),
      screenWidth: screen is Map ? (screen['w'] as num?)?.toInt() : null,
      screenHeight: screen is Map ? (screen['h'] as num?)?.toInt() : null,
      requests: requests
          .whereType<Map>()
          .map((entry) {
            final request = Map<String, dynamic>.from(entry);
            return SharedBrowserRequest(
              userId: request['userId']?.toString() ?? '',
              name: request['name']?.toString() ?? 'Guest',
            );
          })
          .where((request) => request.userId.isNotEmpty)
          .toList(growable: false),
      error: map['error']?.toString(),
    );
  }
}
