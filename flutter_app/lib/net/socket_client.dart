import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

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

/// The URL to hand socket_io_client, with the port made EXPLICIT.
///
/// socket_io_client parses a multi-label HTTPS host — `watch.example.com`,
/// as opposed to `localhost` — as port 0, then builds its handshake URL from
/// what it parsed. The result is a request to
/// `https://host:0/socket.io/?EIO=4&transport=websocket`, which fails with
/// "was not upgraded to websocket" and names neither the port nor the cause.
///
/// [socketOptionsFor] already sets `port` in the options map, and that is not
/// enough on its own: the library builds the URL from the URL, so the options
/// never get a chance to correct it. Writing the port into the URL is what
/// actually reaches the parser.
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
