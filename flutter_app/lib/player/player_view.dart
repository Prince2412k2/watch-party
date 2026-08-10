import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../analog/player_core.dart' show ToastMessage;
import '../cache/range_cache_store.dart' show CachedSpan;
import '../data/api_client.dart';
import '../ui/tokens.dart';
import 'player_chrome.dart';
import 'player_controller.dart';
import 'video_view.dart';

/// Composes [VideoView] + [PlayerChrome] into the single embeddable playback
/// widget (PLAN §4 E4.2/E4.3). The app-wide player host opens a
/// [PlayerController] ahead of time and hands it in.
/// The controller's lifecycle stays with the caller — this widget never
/// disposes one.
class PlayerView extends StatelessWidget {
  const PlayerView({
    super.key,
    required this.controller,
    this.canControl = true,
    this.title,
    this.onBack,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.itemId,
    this.mediaSourceId,
    this.apiClient,
    this.preferredSubtitleStreamIndex,
    this.cachedSpans,
    this.visible,
    this.onWake,
    this.onToggleChat,
    this.onPushToTalkStart,
    this.onPushToTalkStop,
    this.chatOpen = false,
    this.chatToasts = const [],
  });

  /// Ready-made controller supplied by the app-wide player host.
  final PlayerController controller;

  final int? preferredSubtitleStreamIndex;

  /// Read-only transport bar when false — E5 passes this for a guest without
  /// playback-control rights (PLAN §4 E5.2 `canControl` gating).
  final bool canControl;

  /// Optional title shown in the chrome's top bar.
  final String? title;

  /// Optional back affordance in the chrome's top bar.
  final VoidCallback? onBack;

  /// Fullscreen is a window-level concern owned by the caller; chrome only
  /// renders the affordance and calls this.
  final VoidCallback? onToggleFullscreen;
  final bool isFullscreen;

  final String? itemId;
  final String? mediaSourceId;
  final ApiClient? apiClient;

  /// Cached ("downloaded") byte-range spans for [itemId], forwarded straight
  /// to [PlayerChrome]'s seek-bar overlay. Null for the offline-local-file
  /// path (nothing to indicate) or when the caller has no cache proxy.
  final ValueListenable<List<CachedSpan>>? cachedSpans;

  /// Party path only: parent-owned chrome visibility + wake, and the party
  /// key bindings (`c` chat, hold-`T` push-to-talk) — forwarded to
  /// [PlayerChrome]. Null for solo playback (chrome self-manages, keys no-op).
  final bool? visible;
  final VoidCallback? onWake;
  final VoidCallback? onToggleChat;
  final VoidCallback? onPushToTalkStart;
  final VoidCallback? onPushToTalkStop;

  /// Party chat state for the over-player message toasts — forwarded straight
  /// to [PlayerChrome]. Empty in solo playback.
  final bool chatOpen;
  final List<ToastMessage> chatToasts;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoView(controller: controller),
          PlayerChrome(
            controller: controller,
            canControl: canControl,
            title: title,
            onBack: onBack,
            onToggleFullscreen: onToggleFullscreen,
            isFullscreen: isFullscreen,
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            apiClient: apiClient,
            preferredSubtitleStreamIndex: preferredSubtitleStreamIndex,
            cachedSpans: cachedSpans,
            visible: visible,
            onWake: onWake,
            onToggleChat: onToggleChat,
            onPushToTalkStart: onPushToTalkStart,
            onPushToTalkStop: onPushToTalkStop,
            chatOpen: chatOpen,
            chatToasts: chatToasts,
          ),
        ],
      ),
    );
  }
}
