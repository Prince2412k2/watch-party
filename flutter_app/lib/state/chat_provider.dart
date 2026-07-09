import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';

/// Party chat log (PLAN §3.8). Phase 0 keeps an in-memory list; E7 wires it to
/// the `chat:message` socket events (send + receive + rate-limit UX).
class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  ChatNotifier() : super(const []);

  void add(ChatMessage message) => state = [...state, message];

  void addAll(Iterable<ChatMessage> messages) => state = [...state, ...messages];

  void clear() => state = const [];
}

final chatProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) => ChatNotifier());
