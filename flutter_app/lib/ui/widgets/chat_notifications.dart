import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/chrome/analog_toast.dart';
import '../../models/models.dart';
import '../../state/state.dart';
import 'avatar_view.dart';

/// App-wide notices for live chat, including when the player is expanded.
/// History remains in the drawer and does not generate notifications.
class ChatNotifications extends ConsumerWidget {
  const ChatNotifications({super.key, required this.child});

  final Widget child;

  void _announce(BuildContext context, WidgetRef ref, ChatMessage message) {
    if (ref.read(chatDrawerOpenProvider)) return;
    if (message.userId == ref.read(currentUserIdProvider)) return;
    showAnalogToast(
      context,
      _preview(message),
      title: message.name,
      leading: AvatarView(userId: message.userId, name: message.name, size: 34),
    );
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
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ChatMessage?>(liveChatMessageProvider, (_, message) {
      if (message != null) _announce(context, ref, message);
    });
    return child;
  }
}
