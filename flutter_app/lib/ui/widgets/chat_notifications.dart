import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/chrome/analog_toast.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import 'avatar_view.dart';

/// Announces every incoming chat message, wherever the viewer is.
///
/// The app's ONLY chat notification path. It used to be one of two: the player
/// drew its own stack inside the stage, and everywhere else was silent. Both
/// halves were wrong. Browsing the library, a message arrived with no notice at
/// all; inside the player it arrived underneath the floating camera tiles,
/// behind somebody's face.
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

  void _onLog(List<ChatMessage> log) {
    final me = ref.read(currentUserIdProvider);
    // The one thing that silences a message: you are looking at the drawer it
    // is already in. Being in the player is NOT a reason any more — the player
    // used to draw its own stack inside the stage, underneath the floating
    // camera tiles, so a notice arrived behind somebody's face. There is one
    // notification path now and it is above everything.
    final drawerOpen = ref.read(chatDrawerOpenProvider);
    for (final message in log) {
      // Mark seen even when nothing is shown, so closing the drawer does not
      // release a burst of everything that arrived while it was open.
      if (!_seen.add(_keyOf(message))) continue;
      if (drawerOpen) continue;
      if (me != null && message.userId == me) continue;
      showAnalogToast(
        context,
        _preview(message),
        title: message.name,
        leading: AvatarView(
          userId: message.userId,
          name: message.name,
          size: 34,
        ),
      );
    }
  }

  /// Just the message. Who said it is carried by the face and the title, so
  /// repeating the name here would say it three times.
  static String _preview(ChatMessage message) {
    const limit = 90;
    return message.text.length > limit
        ? '${message.text.substring(0, limit).trimRight()}…'
        : message.text;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<ChatMessage>>(chatProvider, (_, next) => _onLog(next));
    return widget.child;
  }
}
