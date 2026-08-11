import 'dart:async';
import 'dart:convert';
import 'dart:io' as io_net;
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
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

/// The connection came up and went away again before it was usable.
///
/// Distinct from [SocketConnectFailure] (never reached the server, or the
/// server refused the handshake) because the two mean opposite things about
/// where to look: this one says the server or the path to it accepted a
/// WebSocket and then dropped it mid-handshake.
class SocketClosedDuringConnect implements Exception {
  const SocketClosedDuringConnect(
    this.reason, {
    this.attempts = 1,
    this.cookieBytes,
    this.close,
    this.engineOpened = false,
  });

  /// Whether the Engine.IO handshake completed before the connection died.
  /// See [SocketDialProbe.engineOpened] — this is the line between a transport
  /// fault and a Socket.IO one.
  final bool engineOpened;

  /// How the underlying WebSocket closed — see [SocketDialProbe]. Null when it
  /// never opened, or closed without a code.
  final String? close;

  /// Length of the `Cookie:` header the handshake carried, or null if it
  /// carried none.
  ///
  /// The VALUE is never reported — it is the session — but its presence is the
  /// first thing worth knowing when a connection is accepted and then dropped.
  /// The server closes a client that never completes the Socket.IO handshake
  /// (`Client.connectTimeout`), and a handshake with no cookie is the ordinary
  /// way to end up there. Same reasoning as [_describeFailedUpgrade], which
  /// reports the length and nothing else.
  final int? cookieBytes;

  /// socket.io's own disconnect reason — 'io server disconnect',
  /// 'transport close', 'ping timeout', 'transport error'. The one fact worth
  /// having, and the one that used to be discarded.
  final Object? reason;

  /// How many dials were made before giving up.
  final int attempts;

  @override
  String toString() =>
      'socket disconnected while connecting (${reason ?? 'no reason given'}'
      '${attempts > 1 ? ', $attempts attempts' : ''}, '
      '${cookieBytes == null ? 'NO session cookie' : 'cookie $cookieBytes bytes'}'
      '${close == null ? '' : ', $close'}'
      ', engine open: ${engineOpened ? 'yes' : 'NO'})';
}

/// FROZEN CONTRACT (PLAN §3.5). A thin, typed wrapper over socket_io_client that
/// speaks the backend's event vocabulary (see `events.dart`). Party controls
/// and chat build on top of this. The mock implementation lets the
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
  Future<void>? _connecting;
  Completer<void>? _connectCompleter;
  final Map<String, Set<void Function(dynamic)>> _handlers = {};
  final _connCtrl = StreamController<bool>.broadcast();

  @override
  Future<void> connect() {
    if (isConnected) return Future<void>.value();
    final connecting = _connecting;
    if (connecting != null) return connecting;
    final future = _connect();
    _connecting = future;
    return future.whenComplete(() {
      if (identical(_connecting, future)) _connecting = null;
    });
  }

  Future<void> _connect() async {
    final cookie = cookieHeader ?? await cookieHeaderProvider?.call();
    final target = socketUrlFor(_url);
    // Logged on every connect so a failure report identifies the build that
    // produced it. A ":0" in the thrown message with NO such line above it
    // means the binary predates socketUrlFor — the same symptom as a broken
    // fix, and previously indistinguishable from one.
    debugPrint('socket.io connecting to $target (from $_url)');

    // Retried, for the same reason the WebSocket dial below is.
    //
    // [connectSocketWebSocket] retries an upgrade the edge answers badly; this
    // covers a socket that comes up and is torn down mid-handshake, which was
    // fatal on the first occurrence.
    //
    // MEASURED, because the obvious theory is wrong: a clean 101 followed by an
    // immediate close does NOT arrive here. socket_io_client reports that as
    // `connect_error` with reason 'timeout' (a fake server doing exactly that
    // was the check), so it surfaces as [SocketConnectFailure] instead. What
    // reaches this path is a disconnect on a socket that had already subscribed
    // — 'io server disconnect', 'transport close', 'ping timeout' — and which
    // of those it is now travels in the error.
    //
    // Deliberately narrow: an auth rejection arrives as `connect_error` and a
    // local teardown as a plain cancellation. Both still fail immediately,
    // because retrying either is just doing the wrong thing three times.
    const attempts = 3;
    const backoff = [Duration(milliseconds: 250), Duration(milliseconds: 750)];
    SocketClosedDuringConnect? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(backoff[attempt - 1]);
      try {
        return await _dial(target, cookie);
      } on SocketClosedDuringConnect catch (e) {
        lastError = e;
      }
    }
    throw SocketClosedDuringConnect(
      lastError!.reason,
      attempts: attempts,
      cookieBytes: cookie?.length,
      close: lastError.close,
      engineOpened: lastError.engineOpened,
    );
  }

  Future<void> _dial(String target, String? cookie) async {
    final probe = SocketDialProbe();
    final socket = io.io(target, socketOptionsFor(_url, cookie, probe: probe));
    _socket = socket;
    final completer = Completer<void>();
    _connectCompleter = completer;
    socket.onConnect((_) {
      _connCtrl.add(true);
      if (!completer.isCompleted) completer.complete();
    });
    socket.onDisconnect((reason) {
      _connCtrl.add(false);
      if (!completer.isCompleted) {
        // The reason is the entire diagnosis and it used to be dropped on the
        // floor: 'io server disconnect' means the server hung up on us,
        // 'transport close' means the link or something in front of it did,
        // 'ping timeout' means heartbeats stopped landing. Three different
        // faults that all read as one unexplained failure without it.
        completer.completeError(
          SocketClosedDuringConnect(
            reason,
            cookieBytes: cookie?.length,
            // Read on the way out: by the time socket.io says 'transport
            // close', dart:io already knows the code the peer closed with —
            // or that there was no close frame at all, which is itself the
            // answer.
            close: probe.closeDescription,
            engineOpened: probe.engineOpened,
          ),
        );
      }
    });
    socket.onConnectError((e) {
      if (!completer.isCompleted) {
        // Carry the resolved target into the error. socket_io_client's own
        // message quotes the URL it built, which is the one piece of evidence
        // that says whether the port fix ran — but only if the two are shown
        // together.
        completer.completeError(SocketConnectFailure(target, e));
      }
    });
    for (final entry in _handlers.entries) {
      for (final handler in entry.value) {
        socket.on(entry.key, handler);
      }
    }
    socket.connect();

    // Where the handshake got to, which is the question the reason string
    // cannot answer.
    //
    // The Engine.IO layer emits 'open' only once the SERVER's OPEN packet has
    // arrived and been parsed. So:
    //   engine open: no  → the server (or the path) never delivered it, and
    //                      nothing above the transport is implicated;
    //   engine open: yes → the transport worked and the Socket.IO CONNECT
    //                      exchange on top of it is what failed.
    // Attached after connect(), which is where the Manager builds the engine.
    probe.engine = socket.io.engine;

    try {
      await completer.future;
    } catch (_) {
      if (identical(_socket, socket)) _socket = null;
      socket.dispose();
      rethrow;
    } finally {
      if (identical(_connectCompleter, completer)) _connectCompleter = null;
    }
  }

  @override
  Future<void> disconnect() async {
    final completer = _connectCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('socket connection cancelled'));
    }
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
    (_handlers[event] ??= {}).add(handler);
    _socket?.on(event, handler);
    return () {
      _handlers[event]?.remove(handler);
      if (_handlers[event]?.isEmpty ?? false) _handlers.remove(event);
      _socket?.off(event, handler);
    };
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
/// Remembers the raw socket of the dial in flight, so a connection that dies
/// during the handshake can be asked HOW it died.
///
/// The WebSocket close code is the difference between "something in the path
/// killed the connection" (1006, no close frame), "the peer closed it politely"
/// (1000/1001) and "one side could not parse the other's frames" (1002/1003).
/// socket.io only ever says 'transport close' for all three.
class SocketDialProbe {
  io_net.WebSocket? raw;

  /// The Engine.IO socket for this dial, once the manager has built one.
  dynamic engine;

  /// Whether the server's Engine.IO handshake packet ever arrived.
  bool get engineOpened => engine?.readyState == 'open';

  /// Null while the socket is open or was never dialled.
  String? get closeDescription {
    final code = raw?.closeCode;
    if (code == null) return null;
    final reason = raw?.closeReason;
    return 'ws close $code'
        '${reason == null || reason.isEmpty ? '' : ' "$reason"'}';
  }
}

Future<ws.WebSocket> connectSocketWebSocket(
  Uri uri, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
  SocketDialProbe? probe,
}) async {
  // `Uri.replace(port:)` normalises a DEFAULT port back out of the string —
  // the trap that made an earlier attempt at this a silent no-op. It is safe
  // here only because Dart has no default port for ws/wss, which is the very
  // gap being worked around: 443 is not the default for `wss`, so it stays.
  final target = uri.hasPort
      ? uri
      : uri.replace(port: uri.isScheme('wss') ? 443 : 80);
  // Retried, because a refused upgrade here is very often not a refusal.
  //
  // Diagnosing a report of this showed the handshake failing and an identical
  // request issued a second later succeeding: 101, correct Sec-WebSocket-Accept,
  // correct Connection/Upgrade headers, session cookie present — every check
  // dart:io makes would have passed on the retry. The endpoint is behind a CDN
  // and some edges intermittently answer an upgrade badly.
  //
  // One failed dial used to be fatal, and that is harsher here than almost
  // anywhere else in the app: `setTransports(['websocket'])` means there is no
  // polling fallback (socket_io_client's native Dart transport cannot complete
  // an Engine.IO session over polling), so a single bad response was the whole
  // connection. Three attempts across roughly a second cost nothing when the
  // first works, which is the overwhelmingly common case.
  //
  // Deliberately NOT a general-purpose retry loop: only the "was not upgraded"
  // family is retried, and only a fixed few times. A server that is genuinely
  // down, refusing auth, or unreachable still fails fast, with the diagnostic
  // from the LAST attempt attached.
  const attempts = 3;
  const backoff = [Duration(milliseconds: 250), Duration(milliseconds: 750)];
  io_net.WebSocketException? lastError;
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (attempt > 0) await Future<void>.delayed(backoff[attempt - 1]);
    try {
      final socket = await io_net.WebSocket.connect(
        target.toString(),
        protocols: protocols,
        headers: headers,
      );
      probe?.raw = socket;
      return IOWebSocket.fromWebSocket(socket);
    } on io_net.WebSocketException catch (e) {
      lastError = e;
    }
  }
  // dart:io throws "was not upgraded to websocket" for ANY non-101 response and
  // throws the response away, so the one fact worth having — what the server
  // actually said — is lost exactly when it is needed. Ask again, in plain
  // HTTP, purely to report it.
  final detail = await _describeFailedUpgrade(target, headers);
  // The package's contract: transports expect ws.WebSocketException.
  throw ws.WebSocketException(
    '${lastError!.message} (dialling $target, $attempts attempts)$detail',
  );
}

/// Re-run the handshake as a plain HTTP request and describe the response.
///
/// Diagnostic only, and only on the failure path — it costs one extra request
/// when a connection has already failed, and nothing at all when things work.
///
/// Response headers are reported from an explicit ALLOWLIST rather than by
/// filtering out anything that looks sensitive. A denylist keyed on header
/// names is exactly how a secret ends up in a log the first time an upstream
/// invents a new name for one. Request headers are never echoed at all: the
/// session cookie rides in those, and its LENGTH is the only thing worth
/// knowing.
Future<String> _describeFailedUpgrade(
  Uri target,
  Map<String, String>? headers,
) async {
  const reportable = {
    'server',
    'content-type',
    'content-length',
    'cf-ray',
    'cf-mitigated',
    'location',
    'retry-after',
    'upgrade',
    'connection',
  };
  final http = io_net.HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final probe = target.replace(
      scheme: target.isScheme('wss') ? 'https' : 'http',
    );
    // A RANDOM key, exactly as the real client sends. A fixed one cannot
    // detect the failure that matters here: dart:io does not only check for a
    // 101, it also verifies that Sec-WebSocket-Accept is the SHA-1 of the key
    // it sent. A proxy or CDN replaying a handshake computed for a different
    // key returns a perfectly good-looking 101 that dart:io still refuses —
    // which is precisely the case where the status line alone misleads.
    final key = base64.encode(
      List<int>.generate(16, (_) => math.Random.secure().nextInt(256)),
    );
    final request = await http.getUrl(probe);
    request.headers.set('Connection', 'Upgrade');
    request.headers.set('Upgrade', 'websocket');
    request.headers.set('Sec-WebSocket-Version', '13');
    request.headers.set('Sec-WebSocket-Key', key);
    headers?.forEach(request.headers.set);
    final response = await request.close();
    final reported = <String>[];
    response.headers.forEach((name, values) {
      if (reportable.contains(name.toLowerCase())) {
        reported.add('$name: ${values.join(', ')}');
      }
    });
    // RFC 6455's fixed GUID: accept = base64(sha1(key + GUID)).
    const wsGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
    final expected = base64.encode(
      sha1.convert(utf8.encode(key + wsGuid)).bytes,
    );
    final actual = response.headers.value('sec-websocket-accept');
    final handshake = response.statusCode != 101
        ? 'not a 101, so the accept was never checked'
        : actual == null
        ? 'MISSING Sec-WebSocket-Accept — a 101 with no handshake to verify'
        : actual == expected
        ? 'accept matches the key we sent'
        : 'ACCEPT MISMATCH — got $actual, expected $expected for this '
              'request\'s key. A 101 computed for somebody else\'s handshake '
              'is what dart:io rejects.';
    await response.drain<void>();
    final cookieLength = headers?['Cookie']?.length ?? 0;
    return '\n  → server replied ${response.statusCode} '
        '${response.reasonPhrase}'
        '\n  → ${reported.isEmpty ? '(no reportable headers)' : reported.join('; ')}'
        '\n  → $handshake'
        '\n  → sent ${headers?.length ?? 0} extra header(s), '
        'cookie ${cookieLength == 0 ? 'ABSENT' : '$cookieLength chars'}';
  } catch (e) {
    return '\n  → could not re-probe the endpoint either: $e';
  } finally {
    http.close(force: true);
  }
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

Map<String, dynamic> socketOptionsFor(
  String url,
  String? cookie, {
  SocketDialProbe? probe,
}) {
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
  options['webSocketConnector'] =
      (
        Uri uri, {
        Iterable<String>? protocols,
        Map<String, String>? headers,
      }) => connectSocketWebSocket(
        uri,
        protocols: protocols,
        headers: headers,
        probe: probe,
      );
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
    for (final h in List.of(_handlers[event] ?? const [])) {
      h(data);
    }
  }

  @override
  Stream<bool> get connectionState => _connCtrl.stream;
}
