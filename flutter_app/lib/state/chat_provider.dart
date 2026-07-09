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

/// Party chat log (PLAN §3.8 / E7). Subscribes to the server's `chat:message`
/// broadcast and sends outgoing messages via the client `chat:message` emit
/// (ack `{ ok }` | `{ error: 'rate limited' }`). Tracks a local send-time
/// window so the UI can show the same "rate limited" state without waiting on
/// a round trip.
class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  ChatNotifier(this._socket) : super(const []) {
    _unsubscribe = _socket.on(ServerEvent.chatMessage, _onIncoming);
  }

  final SocketClient _socket;
  void Function()? _unsubscribe;
  final Queue<DateTime> _sendTimes = Queue();

  void _onIncoming(dynamic data) {
    if (data is! Map) return;
    final json = data.map((k, v) => MapEntry(k.toString(), v));
    final userId = json['userId']?.toString();
    final text = json['text']?.toString();
    if (userId == null || text == null) return;
    final message = ChatMessage(
      userId: userId,
      name: json['name']?.toString() ?? userId,
      text: text,
      timestamp: (json['timestamp'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
    );
    state = [...state, message];
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
  /// empty text, or a server-side error), or null on success.
  Future<String?> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (isRateLimited) return 'Rate limited — slow down.';

    _sendTimes.add(DateTime.now());
    final resp = await _socket.emitWithAck(ClientEvent.chatMessage, {'text': trimmed});
    if (resp is Map && resp['error'] != null) {
      return resp['error'].toString() == 'rate limited'
          ? 'Rate limited — slow down.'
          : resp['error'].toString();
    }
    return null;
  }

  void clear() => state = const [];

  @override
  void dispose() {
    _unsubscribe?.call();
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
