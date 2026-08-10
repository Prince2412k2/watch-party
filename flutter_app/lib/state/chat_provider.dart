import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../net/events.dart';
import '../net/socket_client.dart';
import 'auth_provider.dart';
import 'providers.dart';

/// Mirrors the server's per-socket chat rate limit
/// (`app/server/index.js`: `CHAT_RATE_MAX` messages per `CHAT_RATE_WINDOW_MS`)
/// so the input can warn before the server bounces the send.
const int chatRateMax = 5;
const Duration chatRateWindow = Duration(milliseconds: 3000);

/// How long a send waits for the server's `chat:message` ack before giving up.
/// socket.io acks have no deadline of their own: a socket that dropped between
/// the emit and the ack (or a server that never answers) left the send's future
/// pending forever, so the composer stayed disabled with no way back.
const Duration chatAckTimeout = Duration(seconds: 5);

const String _rateLimitedMessage = 'Rate limited — slow down.';

/// Party chat log (PLAN §3.8 / E7). Subscribes to the server's `chat:message`
/// broadcast and sends outgoing messages via the client `chat:message` emit
/// (ack `{ ok }` | `{ error: 'rate limited' }`). Tracks a local send-time
/// window so the UI can show the same "rate limited" state without waiting on
/// a round trip.
class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  ChatNotifier(this._socket, {this.ackTimeout = chatAckTimeout})
    : super(const []) {
    _unsubscribes = [
      _socket.on(ServerEvent.chatMessage, _onIncoming),
      _socket.on(ServerEvent.chatHistory, _onHistory),
    ];
  }

  final SocketClient _socket;

  /// How long [send] waits for the server ack. Injectable so a test doesn't
  /// have to wait out the real [chatAckTimeout].
  final Duration ackTimeout;

  late final List<void Function()> _unsubscribes;
  String? _partyId;
  bool _acceptingHistory = false;
  List<ChatMessage>? _pendingHistory;
  final Queue<DateTime> _sendTimes = Queue();

  void _onIncoming(dynamic data) {
    if (_partyId == null) return;
    if (data is! Map) return;
    final json = data.map((k, v) => MapEntry(k.toString(), v));
    final userId = json['userId']?.toString();
    final text = json['text']?.toString();
    if (userId == null || text == null) return;
    final message = ChatMessage(
      userId: userId,
      name: json['name']?.toString() ?? userId,
      text: text,
      timestamp:
          (json['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
    state = [...state, message];
  }

  void _onHistory(dynamic data) {
    if (data is! List || (_partyId == null && !_acceptingHistory)) return;
    final history = [
      for (final entry in data)
        if (entry is Map) _messageFrom(entry),
    ];
    if (_partyId == null) {
      _pendingHistory = history;
    } else {
      state = history;
    }
  }

  ChatMessage _messageFrom(Map<dynamic, dynamic> data) {
    final json = data.map((k, v) => MapEntry(k.toString(), v));
    final userId = json['userId']?.toString() ?? '';
    return ChatMessage(
      userId: userId,
      name: json['name']?.toString() ?? userId,
      text: json['text']?.toString() ?? '',
      timestamp:
          (json['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  void prepareForJoin() {
    _partyId = null;
    _acceptingHistory = true;
    _pendingHistory = null;
    state = const [];
  }

  void activate(String partyId) {
    if (_partyId == partyId) return;
    _partyId = partyId;
    _acceptingHistory = false;
    state = _pendingHistory ?? const [];
    _pendingHistory = null;
  }

  void deactivate() {
    _partyId = null;
    _acceptingHistory = false;
    _pendingHistory = null;
    state = const [];
  }

  /// True when a send right now would trip the server's rate limit.
  bool get isRateLimited {
    _pruneSendTimes();
    return _sendTimes.length >= chatRateMax;
  }

  void _pruneSendTimes() {
    final cutoff = DateTime.now().subtract(chatRateWindow);
    while (_sendTimes.isNotEmpty && _sendTimes.first.isBefore(cutoff)) {
      _sendTimes.removeFirst();
    }
  }

  /// Send a chat message. Returns an error message on failure (rate limited,
  /// empty text, a dead/silent socket, or a server-side error), or null on
  /// success.
  ///
  /// Retry policy: a send is never retried automatically. The ack is bounded by
  /// [ackTimeout], and a timeout is genuinely ambiguous — the server may well
  /// have accepted and broadcast the message — so resending would duplicate it
  /// in every other client's log. The user retries by sending again, and the
  /// attempt still counts against the local rate window either way.
  Future<String?> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (isRateLimited) return _rateLimitedMessage;

    _sendTimes.add(DateTime.now());
    try {
      final resp = await _socket
          .emitWithAck(ClientEvent.chatMessage, {'text': trimmed})
          .timeout(ackTimeout);
      if (resp is Map && resp['error'] != null) {
        final error = resp['error'].toString();
        if (error != 'rate limited') return error;
        // The server is already refusing: fill the local window so the composer
        // blocks until it drains instead of hammering through every gap.
        _saturateSendWindow();
        return _rateLimitedMessage;
      }
      return null;
    } on TimeoutException {
      return 'No reply from the server — the message may not have been sent.';
    } catch (_) {
      return 'Could not send — check your connection.';
    }
  }

  void _saturateSendWindow() {
    final now = DateTime.now();
    while (_sendTimes.length < chatRateMax) {
      _sendTimes.add(now);
    }
  }

  void clear() => state = const [];

  @override
  void dispose() {
    for (final unsubscribe in _unsubscribes) {
      unsubscribe();
    }
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, List<ChatMessage>>(
  (ref) => ChatNotifier(ref.watch(socketClientProvider)),
);

/// The current user's id, so the chat panel can align "own" messages.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authProvider).user?.userId,
);
