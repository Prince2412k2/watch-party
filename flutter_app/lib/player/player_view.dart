import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../cache/range_cache_store.dart' show CachedSpan;
import '../data/api_client.dart';
import '../models/playback_info.dart';
import '../models/subtitle_preferences.dart';
import '../ui/tokens.dart';
import 'player_chrome.dart';
import 'player_controller.dart';
import 'video_view.dart';

/// Composes [VideoView] + [PlayerChrome] into the single embeddable playback
/// widget (PLAN §4 E4.2/E4.3). This is the widget E3 (title detail — solo
/// play) and E5 (watch party) mount; both open a [PlayerController] ahead of
/// time and hand it in (party: the controller is shared with `SyncEngine`).
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
    this.onSeek,
    this.itemId,
    this.mediaSourceId,
    this.apiClient,
    this.preferredSubtitleStreamIndex,
    this.partyPlayback,
    this.subtitlePreferences,
    this.canManagePartyMedia = true,
    this.onSetPlaybackTracks,
    this.onSetSubtitlePreferences,
    this.cachedSpans,
    this.visible,
    this.onWake,
    this.onToggleChat,
    this.onPushToTalkStart,
    this.onPushToTalkStop,
  });

  /// Ready-made controller supplied by the caller (party/detail inject one).
  final PlayerController controller;

  final int? preferredSubtitleStreamIndex;
  final PlaybackInfo? partyPlayback;
  final SubtitlePreferences? subtitlePreferences;
  final bool canManagePartyMedia;
  final void Function(int? audioStreamIndex, int subtitleStreamIndex)?
  onSetPlaybackTracks;
  final ValueChanged<SubtitlePreferences>? onSetSubtitlePreferences;

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

  /// Authors a seek to an external owner (the party's sync engine). Only set on
  /// the party path; null for solo playback. Passed straight to [PlayerChrome].
  final ValueChanged<Duration>? onSeek;
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
            onSeek: onSeek,
            title: title,
            onBack: onBack,
            onToggleFullscreen: onToggleFullscreen,
            isFullscreen: isFullscreen,
            itemId: itemId,
            mediaSourceId: mediaSourceId,
            apiClient: apiClient,
            preferredSubtitleStreamIndex: preferredSubtitleStreamIndex,
            partyPlayback: partyPlayback,
            subtitlePreferences: subtitlePreferences,
            canManagePartyMedia: canManagePartyMedia,
            onSetPlaybackTracks: onSetPlaybackTracks,
            onSetSubtitlePreferences: onSetSubtitlePreferences,
            cachedSpans: cachedSpans,
            visible: visible,
            onWake: onWake,
            onToggleChat: onToggleChat,
            onPushToTalkStart: onPushToTalkStart,
            onPushToTalkStop: onPushToTalkStop,
          ),
        ],
      ),
    );
  }
}
