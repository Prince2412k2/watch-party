import 'dart:async';
import 'dart:io' as io_net;

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:web_socket/io_web_socket.dart' show IOWebSocket;
import 'package:web_socket/web_socket.dart' as ws;

import '../app/config.dart';

/// A socket handshake that never completed, with the URL it was attempted
/// against.
///
/// The underlying error already names a URL, but it is the one the LIBRARY
/// built — and the whole class of bug this wraps is the library building a
/// different URL from the one we handed it. Reporting both is what tells the
/// two apart.
class SocketConnectFailure implements Exception {
  const SocketConnectFailure(this.target, this.cause);

  /// The URL passed to socket_io_client, after [socketUrlFor].
  final String target;
  final Object cause;

  @override
  String toString() => 'Could not reach $target — $cause';
}

/// FROZEN CONTRACT (PLAN §3.5). A thin, typed wrapper over socket_io_client that
/// speaks the backend's event vocabulary (see `events.dart`). E5/E7 build the
/// sync engine, party controls, and chat on top of this. The mock impl lets the
/// UI and those engines be developed offline.
abstract class SocketClient {
  /// Repoint at a new origin before [connect]. Runtime-settable so the app can
  /// follow a pasted server URL without being rebuilt.
  set url(String value);

  /// Establish the connection (session cookie carried on the handshake).
  Future<void> connect();

  /// Tear down and release listeners.
  Future<void> disconnect();

  bool get isConnected;

  /// Fire an event with no reply.
  void emit(String event, [Object? data]);

  /// Fire an event and await the server's ack payload.
  Future<dynamic> emitWithAck(String event, [Object? data]);

  /// Subscribe to a server event. Returns an unsubscribe callback.
  void Function() on(String event, void Function(dynamic data) handler);

  /// Connection lifecycle (true = connected).
  Stream<bool> get connectionState;
}

/// socket_io_client-backed implementation.
///
/// The session cookie must ride along on the handshake. On desktop, dart:io
/// sockets don't share dio's cookie jar automatically, so the `connect.sid`
/// cookie value is injected via [cookieHeader] (E2 wires it from the
/// [DioApiClient]'s jar). Same origin as [AppConfig.apiBase].
class IoSocketClient implements SocketClient {
  IoSocketClient({String? url, this.cookieHeader, this.cookieHeaderProvider})
    : _url = url ?? AppConfig.socketUrl;

  String _url;

  @override
  set url(String value) => _url = value;

  /// Full `Cookie:` header value (e.g. `connect.sid=s%3A...`).
  final String? cookieHeader;

  /// Alternative to [cookieHeader] for a caller that can't compute the header
  /// synchronously at construction time (e.g. reading a [DioApiClient]'s
  /// [CookieJar] happens after login, well after the socket client is built
  /// and DI-wired). Resolved once per [connect] call when [cookieHeader] is
  /// null.
  final Future<String?> Function()? cookieHeaderProvider;

  io.Socket? _socket;
  final _connCtrl = StreamController<bool>.broadcast();

  @override
  Future<void> connect() async {
    final cookie = cookieHeader ?? await cookieHeaderProvider?.call();
    final target = socketUrlFor(_url);
    // Logged on every connect so a failure report identifies the build that
    // produced it. A ":0" in the thrown message with NO such line above it
    // means the binary predates socketUrlFor — the same symptom as a broken
    // fix, and previously indistinguishable from one.
    debugPrint('socket.io connecting to $target (from $_url)');
    final socket = io.io(target, socketOptionsFor(_url, cookie));
    _socket = socket;
    final completer = Completer<void>();
    socket.onConnect((_) {
      _connCtrl.add(true);
      if (!completer.isCompleted) completer.complete();
    });
    socket.onDisconnect((_) => _connCtrl.add(false));
    socket.onConnectError((e) {
      if (!completer.isCompleted) {
        // Carry the resolved target into the error. socket_io_client's own
        // message quotes the URL it built, which is the one piece of evidence
        // that says whether the port fix ran — but only if the two are shown
        // together.
        completer.completeError(SocketConnectFailure(target, e));
      }
    });
    socket.connect();
    return completer.future;
  }

  @override
  Future<void> disconnect() async {
    _socket?.dispose();
    _socket = null;
    _connCtrl.add(false);
  }

  @override
  bool get isConnected => _socket?.connected ?? false;

  @override
  void emit(String event, [Object? data]) => _socket?.emit(event, data);

  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) {
    final socket = _socket;
    if (socket == null) {
      return Future.error(StateError('socket not connected'));
    }
    final completer = Completer<dynamic>();
    socket.emitWithAck(
      event,
      data ?? const {},
      ack: (resp) {
        if (!completer.isCompleted) completer.complete(resp);
      },
    );
    return completer.future;
  }

  @override
  void Function() on(String event, void Function(dynamic data) handler) {
    _socket?.on(event, handler);
    return () => _socket?.off(event, handler);
  }

  @override
  Stream<bool> get connectionState => _connCtrl.stream;
}

/// Dial a WebSocket with the port written into the URL.
///
/// THIS is the fix for the `:0` handshake failure. The cause is a defect in
/// socket_io_client 3.1.6 that nothing on our side of the URL could reach:
///
/// 1. `Transport._port()` omits the port whenever it equals the scheme's
///    default, so the transport builds `wss://host/socket.io/?...` with no
///    port — correct-looking, and correct for a browser.
/// 2. `dart:io`'s `WebSocket.connect` re-parses that string and rebuilds it as
///    an HTTPS request, copying `uri.port` across. But Dart only knows default
///    ports for `http` and `https`; for `wss` it has none, so `uri.port`
///    returns **0**.
/// 3. The request therefore goes to `https://host:0/socket.io/?...`, which
///    cannot connect, and the exception quotes that URL — including the empty
///    trailing `#` that a `Uri` with an empty fragment prints.
///
/// The port is dropped INSIDE the library, after our URL has been consumed, so
/// passing an explicit `:443` up front cannot prevent it — which is exactly
/// what we observed: the client logged `:443` and the failure still said `:0`.
///
/// `webSocketConnector` is the package's own hook for supplying the dial, and
/// [Manager] forwards it into the websocket transport's options. Restoring the
/// port here is the last point before `dart:io` parses the string.
///
/// [headers] carries `setExtraHeaders`, i.e. the session cookie, and must be
/// forwarded — the package's default connector does the same, and dropping it
/// would trade a connection failure for an authentication one.
Future<ws.WebSocket> connectSocketWebSocket(
  Uri uri, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
}) async {
  // `Uri.replace(port:)` normalises a DEFAULT port back out of the string —
  // the trap that made an earlier attempt at this a silent no-op. It is safe
  // here only because Dart has no default port for ws/wss, which is the very
  // gap being worked around: 443 is not the default for `wss`, so it stays.
  final target = uri.hasPort
      ? uri
      : uri.replace(port: uri.isScheme('wss') ? 443 : 80);
  final io_net.WebSocket socket;
  try {
    socket = await io_net.WebSocket.connect(
      target.toString(),
      protocols: protocols,
      headers: headers,
    );
  } on io_net.WebSocketException catch (e) {
    // The package's contract: transports expect ws.WebSocketException.
    throw ws.WebSocketException('${e.message} (dialling $target)');
  }
  return IOWebSocket.fromWebSocket(socket);
}

/// The URL to hand socket_io_client, with the port made EXPLICIT.
///
/// Belt and braces alongside [connectSocketWebSocket], which is what actually
/// fixes the `:0` failure. This only settles what the engine records as the
/// origin; it does NOT survive into the transport's URL, because
/// `Transport._port()` strips a default port again on the way out.
///
/// Kept because it costs nothing, it makes the intended port visible in the
/// connect log, and it guards the separate case of an engine that cannot infer
/// a port at all.
///
/// A URL that already carries a port is returned untouched, so `localhost:3005`
/// and any tailnet address keep working exactly as before.
String socketUrlFor(String url) {
  final uri = Uri.parse(url);
  if (uri.hasPort) return url;
  final port = const {'https', 'wss'}.contains(uri.scheme) ? 443 : 80;
  // Built by hand rather than with `uri.replace(port: port)`. Dart NORMALISES
  // a default port out of a URI's string form, so replace(port: 443) on an
  // https URI round-trips back to the original with no port at all — the
  // first version of this fix compiled, read correctly, and did nothing. The
  // test below is what caught it.
  final path = uri.path.isEmpty ? '' : uri.path;
  return '${uri.scheme}://${uri.host}:$port$path';
}

Map<String, dynamic> socketOptionsFor(String url, String? cookie) {
  final uri = Uri.parse(url);
  final builder = io.OptionBuilder()
      // Native Dart only implements the WebSocket transport. Listing polling
      // first makes socket_io_client open a WebSocket with transport=polling,
      // which receives a 101 but can never complete the Engine.IO session.
      .setTransports(['websocket'])
      .disableAutoConnect()
      .enableForceNew();
  if (cookie != null) builder.setExtraHeaders({'Cookie': cookie});
  final options = Map<String, dynamic>.from(builder.build());
  // The dial itself, so the port survives into dart:io. See
  // [connectSocketWebSocket] for why nothing earlier in the chain can do this.
  options['webSocketConnector'] = connectSocketWebSocket;
  // socket_io_client <=3.1.3 parsed multi-label HTTPS hosts as port 0. Keep an
  // explicit default in our own options so persisted origins remain safe even
  // if dependency resolution or an older packaged binary regresses.
  options['port'] = uri.port == 0
      ? (const {'https', 'wss'}.contains(uri.scheme) ? 443 : 80)
      : uri.port;
  return options;
}

/// Offline mock: records emissions, lets tests inject inbound events.
class MockSocketClient implements SocketClient {
  final _connCtrl = StreamController<bool>.broadcast();
  final _handlers = <String, List<void Function(dynamic)>>{};
  bool _connected = false;

  /// Everything emitted, for assertions.
  final List<(String, Object?)> emitted = [];

  @override
  set url(String value) {}

  @override
  Future<void> connect() async {
    _connected = true;
    _connCtrl.add(true);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _connCtrl.add(false);
  }

  @override
  bool get isConnected => _connected;

  @override
  void emit(String event, [Object? data]) => emitted.add((event, data));

  @override
  Future<dynamic> emitWithAck(String event, [Object? data]) async {
    emitted.add((event, data));
    return {'ok': true};
  }

  @override
  void Function() on(String event, void Function(dynamic data) handler) {
    (_handlers[event] ??= []).add(handler);
    return () => _handlers[event]?.remove(handler);
  }

  /// Test helper: deliver an inbound server event to registered handlers.
  void inject(String event, dynamic data) {
    for (final h in _handlers[event] ?? const []) {
      h(data);
    }
  }

  @override
  Stream<bool> get connectionState => _connCtrl.stream;
}
