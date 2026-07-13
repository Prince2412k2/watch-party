import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../app/config.dart';
import '../models/models.dart';

/// Aggregated landing payload from `GET /api/library/home`.
class HomeData {
  const HomeData({
    this.views = const [],
    this.resume = const [],
    this.nextUp = const [],
  });

  final List<LibraryItem> views;
  final List<LibraryItem> resume;
  final List<LibraryItem> nextUp;

  factory HomeData.fromJson(Map<String, dynamic> json) {
    List<LibraryItem> parse(String key) => ((json[key] as List?) ?? const [])
        .map((e) => LibraryItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return HomeData(
      views: parse('views'),
      resume: parse('resume'),
      nextUp: parse('nextUp'),
    );
  }
}

/// Credentials for joining a LiveKit room, from `GET /api/livekit/token`.
class LiveKitToken {
  const LiveKitToken({required this.token, required this.url, this.iceServers});

  final String token;
  final String url;
  final List<Map<String, dynamic>>? iceServers;

  factory LiveKitToken.fromJson(Map<String, dynamic> json) => LiveKitToken(
    token: json['token'] as String,
    url: json['url'] as String,
    iceServers: (json['iceServers'] as List?)?.cast<Map<String, dynamic>>(),
  );
}

/// Image kinds the server's `/api/library/image` proxy accepts.
enum ImageType { primary, backdrop, thumb, logo, banner, art }

extension on ImageType {
  String get jellyfin => switch (this) {
    ImageType.primary => 'Primary',
    ImageType.backdrop => 'Backdrop',
    ImageType.thumb => 'Thumb',
    ImageType.logo => 'Logo',
    ImageType.banner => 'Banner',
    ImageType.art => 'Art',
  };
}

/// FROZEN CONTRACT (PLAN §3.2). The full surface the app uses to talk to the
/// backend. `DioApiClient` is the real impl; `MockApiClient` backs tests/gallery.
abstract class ApiClient {
  // ── Server ────────────────────────────────────────────────────────────
  /// The backend origin this client talks to. Runtime-settable so the app can
  /// point at a pasted server URL without being rebuilt.
  String get baseUrl;
  set baseUrl(String value);

  // ── Auth ──────────────────────────────────────────────────────────────
  Future<User> login(String username, String password);
  Future<User> me();
  Future<void> logout();

  // ── Library ───────────────────────────────────────────────────────────
  Future<HomeData> home();
  Future<List<LibraryItem>> items({String? parentId});
  Future<List<LibraryItem>> children(String itemId);
  Future<LibraryItem> item(String id);
  Future<List<LibraryItem>> latest({String? parentId});
  Future<List<LibraryItem>> search(String query);
  Future<TrickplayManifest> trickplay(String itemId, {String? mediaSourceId});

  /// Absolute URL to a proxied poster/backdrop image.
  String imageUrl(
    String itemId, {
    ImageType type = ImageType.primary,
    String? tag,
  });

  // ── Playback / offline ─────────────────────────────────────────────────
  /// Mint a short-lived signed URL for direct-play (`purpose: 'stream'`) or
  /// resumable download (`purpose: 'download'`).
  Future<StreamUrl> nativeStreamUrl(String itemId, {String purpose = 'stream'});

  /// The audio/subtitle tracks available for [itemId] (`POST
  /// /api/library/playback-info/:id`), optionally re-selecting a track.
  Future<PlaybackInfo> playbackInfo(
    String itemId, {
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  });

  /// Raw subtitle text for a Jellyfin stream index.
  Future<String> subtitleContent(
    String itemId,
    int streamIndex, {
    String? mediaSourceId,
  });

  /// Upload an external subtitle file for [itemId]. [filename] is used only
  /// to infer the subtitle format (its extension) and label.
  Future<void> uploadSubtitle(String itemId, List<int> bytes, String filename);

  /// Delete the external subtitle track at [streamIndex] on [itemId].
  Future<void> deleteSubtitle(String itemId, int streamIndex);

  // ── LiveKit ─────────────────────────────────────────────────────────────
  Future<LiveKitToken> livekitToken(String partyId);

  // ── Servarr (radarr/sonarr/prowlarr/qbittorrent/bazarr proxy) ──────────
  /// Generic passthrough to `GET /api/servarr/<path>`.
  Future<dynamic> servarrGet(String path, {Map<String, dynamic>? query});

  /// Generic passthrough to `POST /api/servarr/<path>`.
  Future<dynamic> servarrPost(String path, {Object? body});

  /// Generic passthrough to `DELETE /api/servarr/<path>`.
  Future<dynamic> servarrDelete(String path, {Map<String, dynamic>? query});

  /// Absolute URL to the servarr poster proxy (`/api/servarr/image`).
  String servarrImageUrl(String remoteUrl);
}

/// Concrete dio-backed client. A [PersistCookieJar] keeps the `connect.sid`
/// session cookie across restarts, so login survives an app relaunch.
class DioApiClient implements ApiClient {
  DioApiClient({Dio? dio, CookieJar? cookieJar, String? baseUrl})
    : _cookieJar = cookieJar ?? CookieJar(),
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? AppConfig.apiBase,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              // We inspect non-2xx ourselves for auth flows.
              // Handle every HTTP response below ourselves so the UI receives
              // the API's concise error instead of Dio's exception dump.
              validateStatus: (s) => s != null && s < 600,
            ),
          ) {
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  final Dio _dio;
  final CookieJar _cookieJar;

  // Flutter's Image.network uses its own HTTP client, not dio's — so it never
  // carries the session cookie dio_cookie_manager attaches automatically.
  // Cached here (refreshed on login/session-restore/logout) so image widgets
  // can attach it explicitly via [cookieHeader]. See [AuthedNetworkImage].
  String? _cookieHeader;

  /// Current `Cookie:` header value for [baseUrl], or null if no session
  /// cookie is stored yet. Synchronous — backed by [_cookieHeader], kept
  /// fresh by [_refreshCookieHeader].
  String? get cookieHeader => _cookieHeader;

  Future<void> _refreshCookieHeader() async {
    final cookies = await _cookieJar.loadForRequest(Uri.parse(baseUrl));
    _cookieHeader = cookies.isEmpty
        ? null
        : cookies.map((c) => '${c.name}=${c.value}').join('; ');
  }

  String get _base => _dio.options.baseUrl;

  @override
  String get baseUrl => _dio.options.baseUrl;

  /// Repoint this client at a new backend origin (all `/api/...`, image, and
  /// native-stream URLs derive from [_base], so this switches everything).
  @override
  set baseUrl(String value) => _dio.options.baseUrl = value;

  Dio get raw => _dio;
  CookieJar get cookieJar => _cookieJar;

  /// Build a [DioApiClient] whose cookie jar persists under [dir].
  static Future<DioApiClient> persistent(String dir, {String? baseUrl}) async {
    await Directory(dir).create(recursive: true);
    final jar = PersistCookieJar(storage: FileStorage(dir));
    return DioApiClient(cookieJar: jar, baseUrl: baseUrl);
  }

  Never _fail(Response res, String what) {
    final body = res.data;
    final msg = (body is Map && body['error'] != null)
        ? body['error'].toString()
        : 'HTTP ${res.statusCode}';
    throw ApiException(what, res.statusCode ?? 0, msg);
  }

  List<LibraryItem> _items(dynamic data) => (data as List)
      .map((e) => LibraryItem.fromJson(e as Map<String, dynamic>))
      .toList();

  @override
  Future<User> login(String username, String password) async {
    final res = await _dio.post(
      '/api/auth/login',
      data: {'username': username, 'password': password},
    );
    if (res.statusCode != 200) _fail(res, 'login');
    await _refreshCookieHeader();
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<User> me() async {
    final res = await _dio.get('/api/auth/me');
    if (res.statusCode != 200) _fail(res, 'me');
    await _refreshCookieHeader();
    return User.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<void> logout() async {
    await _dio.post('/api/auth/logout');
    _cookieHeader = null;
  }

  @override
  Future<HomeData> home() async {
    final res = await _dio.get('/api/library/home');
    if (res.statusCode != 200) _fail(res, 'home');
    return HomeData.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<List<LibraryItem>> items({String? parentId}) async {
    final res = await _dio.get(
      '/api/library/items',
      queryParameters: parentId != null ? {'parentId': parentId} : null,
    );
    if (res.statusCode != 200) _fail(res, 'items');
    return _items(res.data);
  }

  @override
  Future<List<LibraryItem>> children(String itemId) async {
    final res = await _dio.get('/api/library/items/$itemId/children');
    if (res.statusCode != 200) _fail(res, 'children');
    return _items(res.data);
  }

  @override
  Future<LibraryItem> item(String id) async {
    final res = await _dio.get('/api/library/item/$id');
    if (res.statusCode != 200) _fail(res, 'item');
    return LibraryItem.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<List<LibraryItem>> latest({String? parentId}) async {
    final res = await _dio.get(
      '/api/library/latest',
      queryParameters: parentId != null ? {'parentId': parentId} : null,
    );
    if (res.statusCode != 200) _fail(res, 'latest');
    return _items(res.data);
  }

  @override
  Future<List<LibraryItem>> search(String query) async {
    // The server exposes search via the Jellyfin-backed items list; a
    // dedicated endpoint may be added by E3. For now filter the library.
    final all = await items();
    final q = query.toLowerCase();
    return all.where((i) => i.name.toLowerCase().contains(q)).toList();
  }

  @override
  Future<TrickplayManifest> trickplay(
    String itemId, {
    String? mediaSourceId,
  }) async {
    final res = await _dio.get(
      '/api/library/items/$itemId/trickplay',
      queryParameters: mediaSourceId == null
          ? null
          : {'mediaSourceId': mediaSourceId},
    );
    if (res.statusCode != 200) _fail(res, 'trickplay');
    return TrickplayManifest.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  String imageUrl(
    String itemId, {
    ImageType type = ImageType.primary,
    String? tag,
  }) {
    final params = <String, String>{'type': type.jellyfin};
    if (tag != null) params['tag'] = tag;
    final qs = Uri(queryParameters: params).query;
    return '$_base/api/library/image/$itemId?$qs';
  }

  @override
  Future<StreamUrl> nativeStreamUrl(
    String itemId, {
    String purpose = 'stream',
  }) async {
    final res = await _dio.get(
      '/api/library/native/stream-url/$itemId',
      queryParameters: {'purpose': purpose},
    );
    if (res.statusCode != 200) _fail(res, 'nativeStreamUrl');
    return StreamUrl.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<PlaybackInfo> playbackInfo(
    String itemId, {
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final res = await _dio.post(
      '/api/library/playback-info/$itemId',
      data: {
        'mediaSourceId': ?mediaSourceId,
        'audioStreamIndex': ?audioStreamIndex,
        'subtitleStreamIndex': ?subtitleStreamIndex,
      },
    );
    if (res.statusCode != 200) _fail(res, 'playbackInfo');
    return PlaybackInfo.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<String> subtitleContent(
    String itemId,
    int streamIndex, {
    String? mediaSourceId,
  }) async {
    final res = await _dio.get<String>(
      '/api/library/items/$itemId/subtitles/$streamIndex/content',
      queryParameters: mediaSourceId == null
          ? null
          : {'mediaSourceId': mediaSourceId},
      options: Options(responseType: ResponseType.plain),
    );
    if (res.statusCode != 200) _fail(res, 'subtitleContent');
    return res.data ?? '';
  }

  @override
  Future<void> uploadSubtitle(
    String itemId,
    List<int> bytes,
    String filename,
  ) async {
    final res = await _dio.post(
      '/api/library/items/$itemId/subtitles',
      data: Stream.fromIterable([bytes]),
      options: Options(
        headers: {
          Headers.contentLengthHeader: bytes.length,
          'Content-Type': 'application/octet-stream',
          'X-Subtitle-Filename': Uri.encodeComponent(filename),
        },
      ),
    );
    if (res.statusCode != 201) _fail(res, 'uploadSubtitle');
  }

  @override
  Future<void> deleteSubtitle(String itemId, int streamIndex) async {
    final res = await _dio.delete(
      '/api/library/items/$itemId/subtitles/$streamIndex',
    );
    if (res.statusCode != 200) _fail(res, 'deleteSubtitle');
  }

  @override
  Future<LiveKitToken> livekitToken(String partyId) async {
    final res = await _dio.get(
      '/api/livekit/token',
      queryParameters: {'partyId': partyId},
    );
    if (res.statusCode != 200) _fail(res, 'livekitToken');
    return LiveKitToken.fromJson(res.data as Map<String, dynamic>);
  }

  @override
  Future<dynamic> servarrGet(String path, {Map<String, dynamic>? query}) async {
    final res = await _dio.get('/api/servarr/$path', queryParameters: query);
    if (res.statusCode != null && res.statusCode! >= 400) {
      _fail(res, 'servarr GET $path');
    }
    return res.data;
  }

  @override
  Future<dynamic> servarrPost(String path, {Object? body}) async {
    final res = await _dio.post('/api/servarr/$path', data: body);
    if (res.statusCode != null && res.statusCode! >= 400) {
      _fail(res, 'servarr POST $path');
    }
    return res.data;
  }

  @override
  Future<dynamic> servarrDelete(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final res = await _dio.delete('/api/servarr/$path', queryParameters: query);
    if (res.statusCode != null && res.statusCode! >= 400) {
      _fail(res, 'servarr DELETE $path');
    }
    return res.data;
  }

  @override
  String servarrImageUrl(String remoteUrl) =>
      '$_base/api/servarr/image?url=${Uri.encodeQueryComponent(remoteUrl)}';
}

/// Thrown on a non-success API response.
class ApiException implements Exception {
  ApiException(this.operation, this.statusCode, this.message);
  final String operation;
  final int statusCode;
  final String message;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($operation → $statusCode: $message)';
}
