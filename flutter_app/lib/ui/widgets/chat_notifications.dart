import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/chrome/analog_toast.dart';
import '../../models/models.dart';
import '../../state/state.dart';

/// Raises a toast for a chat message that arrives while the viewer is anywhere
/// EXCEPT the player.
///
/// The player has always shown its own chat toasts, and nothing else did — so a
/// message sent while someone was browsing the library, reading a detail page
/// or sitting in the lobby arrived silently and stayed silent until they opened
/// the drawer. That is the whole gap this closes.
///
/// It is mounted once, directly under [AnalogToastHost] and above the router,
/// for the same reason the host is: the chat socket's handlers outlive every
/// screen, so a per-screen listener would miss exactly the messages that matter
/// — the ones that arrive while you are somewhere else.
///
/// Ownership is split cleanly rather than duplicated: while the player is on
/// screen it owns the presentation (its own top-left stack, its own suppression
/// when the drawer is open), and this stays quiet. Both paths mark a message
/// seen either way, so walking out of the player never dumps a backlog.
class ChatNotifications extends ConsumerStatefulWidget {
  const ChatNotifications({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ChatNotifications> createState() => _ChatNotificationsState();
}

class _ChatNotificationsState extends ConsumerState<ChatNotifications> {
  /// Messages already accounted for. Kept separately from the log because the
  /// log is rebuilt wholesale on every change: without this, every rebuild
  /// would re-announce the entire history.
  final Set<String> _seen = {};

  @override
  void initState() {
    super.initState();
    // Whatever is already in the log at mount is history, not news. Joining a
    // party mid-conversation must not fire the backlog at the viewer — the same
    // rule the player's own queue follows when it seeds.
    for (final message in ref.read(chatProvider)) {
      _seen.add(_keyOf(message));
    }
  }

  static String _keyOf(ChatMessage m) =>
      '${m.userId}:${m.timestamp}:${m.text.hashCode}';

  /// True while the player is presenting its own chat toasts.
  ///
  /// Deliberately NOT just "a party exists": the party survives a minimize —
  /// socket, A/V and playback all stay live behind the popcorn — and that is
  /// precisely the case where a notice is most wanted, because the player is no
  /// longer on screen to give one.
  bool get _playerIsShowing {
    final party = ref.read(partyProvider);
    if (party == null || party.stage != 'watching') return false;
    return ref.read(partyMinimizedProvider) != party.id;
  }

  void _onLog(List<ChatMessage> log) {
    final me = ref.read(currentUserIdProvider);
    for (final message in log) {
      // Mark seen even when nothing is shown, so leaving the player does not
      // release a burst of everything that arrived while it was open.
      if (!_seen.add(_keyOf(message))) continue;
      if (_playerIsShowing) continue;
      if (me != null && message.userId == me) continue;
      showAnalogToast(context, _preview(message));
    }
  }

  /// Sender and text on one line, clipped. A toast is a nudge to open the
  /// drawer, not a replacement for reading it.
  static String _preview(ChatMessage message) {
    const limit = 90;
    final text = message.text.length > limit
        ? '${message.text.substring(0, limit).trimRight()}…'
        : message.text;
    return '${message.name}: $text';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<ChatMessage>>(chatProvider, (_, next) => _onLog(next));
    return widget.child;
  }
}
