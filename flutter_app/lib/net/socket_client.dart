import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../app/config.dart';

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
    final builder = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableForceNew();
    if (cookie != null) {
      builder.setExtraHeaders({'Cookie': cookie});
    }
    final socket = io.io(_url, builder.build());
    _socket = socket;
    final completer = Completer<void>();
    socket.onConnect((_) {
      _connCtrl.add(true);
      if (!completer.isCompleted) completer.complete();
    });
    socket.onDisconnect((_) => _connCtrl.add(false));
    socket.onConnectError((e) {
      if (!completer.isCompleted) completer.completeError(e);
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
    socket.emitWithAck(event, data ?? const {}, ack: (resp) {
      if (!completer.isCompleted) completer.complete(resp);
    });
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
