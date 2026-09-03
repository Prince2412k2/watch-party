import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../analog/player_core.dart' show ToastMessage;
import '../analog/player/analog_timeline.dart' show TimelinePeerPosition;
import '../cache/range_cache_store.dart' show CachedSpan;
import '../data/api_client.dart';
import '../ui/tokens.dart';
import '../sync/sync_engine.dart';
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
    this.canManageTracks = true,
    this.onSeekAuthored,
    this.onTogglePlay,
    this.onAudioStreamSelected,
    this.onSubtitleStreamSelected,
    this.onRetryPlayback,
    this.playbackAttempt = 0,
    this.title,
    this.onBack,
    this.onToggleFullscreen,
    this.isFullscreen = false,
    this.itemId,
    this.mediaSourceId,
    this.apiClient,
    this.preferredSubtitleStreamIndex,
    this.subtitleRevision = 0,
    this.cachedSpans,
    this.peerPositions = const [],
    this.catchUp,
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
  final int subtitleRevision;

  /// Read-only transport bar when false — E5 passes this for a guest without
  /// playback-control rights (PLAN §4 E5.2 `canControl` gating).
  final bool canControl;
  final bool canManageTracks;

  /// Called with every seek this viewer authors, so a party can publish it to
  /// the room. Null when nothing is listening (solo playback).
  final ValueChanged<Duration>? onSeekAuthored;
  final Future<void> Function()? onTogglePlay;
  final Future<void> Function(int? index)? onAudioStreamSelected;
  final Future<void> Function(int? index)? onSubtitleStreamSelected;
  final VoidCallback? onRetryPlayback;
  final int playbackAttempt;

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
  final List<TimelinePeerPosition> peerPositions;
  final Stream<CatchUp>? catchUp;

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
            canManageTracks: canManageTracks,
            onSeekAuthored: onSeekAuthored,
            onTogglePlay: onTogglePlay,
            onAudioStreamSelected: onAudioStreamSelected,
            onSubtitleStreamSelected: onSubtitleStreamSelected,
            onRetryPlayback: onRetryPlayback,
            playbackAttempt: playbackAttempt,
            title: title,
            onBack: onBack,
            onToggleFullscreen: onToggleFullscreen,
            isFullscreen: isFullscreen,
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            apiClient: apiClient,
            preferredSubtitleStreamIndex: preferredSubtitleStreamIndex,
            subtitleRevision: subtitleRevision,
            cachedSpans: cachedSpans,
            peerPositions: peerPositions,
            visible: visible,
            onWake: onWake,
            onToggleChat: onToggleChat,
            onPushToTalkStart: onPushToTalkStart,
            onPushToTalkStop: onPushToTalkStop,
            chatOpen: chatOpen,
            chatToasts: chatToasts,
          ),
          if (catchUp != null)
            Positioned(
              top: 20,
              left: 0,
              right: 0,
              child: IgnorePointer(child: _CatchUpBadge(stream: catchUp!)),
            ),
        ],
      ),
    );
  }
}

class _CatchUpBadge extends StatelessWidget {
  const _CatchUpBadge({required this.stream});

  final Stream<CatchUp> stream;

  @override
  Widget build(BuildContext context) => StreamBuilder<CatchUp>(
    stream: stream,
    initialData: CatchUp.idle,
    builder: (context, snapshot) {
      final catchUp = snapshot.data ?? CatchUp.idle;
      if (!catchUp.active) return const SizedBox.shrink();
      return Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC0A0A0B),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              catchUp.behind
                  ? 'Tailing · ${catchUp.rate.toStringAsFixed(2)}×'
                  : 'Synchronizing · ${catchUp.rate.toStringAsFixed(2)}×',
              style: const TextStyle(color: Color(0xFFF4F4F5), fontSize: 12),
            ),
          ),
        ),
      );
    },
  );
}
