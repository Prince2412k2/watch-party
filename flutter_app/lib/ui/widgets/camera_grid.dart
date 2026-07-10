import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../livekit/livekit_room.dart';
import '../../state/livekit_provider.dart';
import '../tokens.dart';

/// Layout mode for [CameraGrid] — E5's party screen picks the mode that fits
/// the docked panel it mounts this into.
enum CameraGridLayout {
  /// Even grid, all tiles the same size.
  grid,

  /// A thin strip of small tiles (e.g. a sidebar rail beside the player).
  strip,
}

/// Renders participant video tiles (local + remote) for the current LiveKit
/// room: talking indicator, name label, mute/cam-off states, hide-self. This
/// is the widget E5's party screen docks beside the player — keep the name
/// `CameraGrid` and mount it with `ProviderScope` already in the tree (it
/// reads [livekitProvider]; it does not connect the room itself).
class CameraGrid extends ConsumerWidget {
  const CameraGrid({
    super.key,
    this.layout = CameraGridLayout.grid,
  });

  final CameraGridLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lkState = ref.watch(livekitProvider);
    final tiles = lkState.tracks
        .where((t) => !(t.isLocal && lkState.hideSelf))
        .toList();

    if (!lkState.connected) {
      return _EmptyGrid(connecting: lkState.connecting, error: lkState.error);
    }
    if (tiles.isEmpty) {
      return const _EmptyGrid(connecting: false, error: null);
    }

    final tileSize = layout == CameraGridLayout.strip ? 160.0 : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (layout == CameraGridLayout.strip) {
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.sm),
            itemCount: tiles.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => SizedBox(
              height: tileSize,
              child: _CameraTile(track: tiles[i]),
            ),
          );
        }

        final columns = tiles.length <= 1
            ? 1
            : tiles.length <= 4
                ? 2
                : 3;
        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.sm),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 4 / 3,
          ),
          itemCount: tiles.length,
          itemBuilder: (_, i) => _CameraTile(track: tiles[i]),
        );
      },
    );
  }
}

class _EmptyGrid extends StatelessWidget {
  const _EmptyGrid({required this.connecting, required this.error});

  final bool connecting;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final label = error != null
        ? 'A/V error: $error'
        : connecting
            ? 'Connecting…'
            : 'Not connected';
    return Center(
      child: Text(
        label,
        style: const TextStyle(color: AppColors.faint, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _CameraTile extends StatelessWidget {
  const _CameraTile({required this.track});

  final ParticipantTrack track;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(
          color: track.isSpeaking ? AppColors.live : AppColors.line,
          width: track.isSpeaking ? 1.5 : 1,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraVideoView(track: track),
          Positioned(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: _NameTag(track: track),
          ),
          if (track.isSpeaking)
            Positioned(
              right: AppSpacing.xs,
              top: AppSpacing.xs,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.live,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Just the video surface for one participant: the live [lk.VideoTrackRenderer]
/// when a camera track is present and unmuted, otherwise the camera-off
/// placeholder. Shared by [CameraGrid]'s docked tiles and the floating PiP
/// tiles ([FloatingCameraTile]) so both render identical video.
class CameraVideoView extends StatelessWidget {
  const CameraVideoView({super.key, required this.track});

  final ParticipantTrack track;

  @override
  Widget build(BuildContext context) {
    // Keep the VideoTrackRenderer MOUNTED for the whole life of the track, and
    // just overlay the cam-off placeholder when muted. Swapping the renderer
    // out on mute (the old behaviour) destroyed and recreated the native
    // RTCVideoRenderer/texture on every toggle — that init runs on the
    // platform thread (UI freeze) and churns the peer-connection event channel
    // (the recurring "No active stream to cancel"). A stable ValueKey keeps the
    // renderer's State across parent rebuilds so it is never re-initialised.
    final videoTrack = track.videoTrack;
    if (videoTrack != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          lk.VideoTrackRenderer(videoTrack, key: ValueKey(videoTrack.sid)),
          if (track.videoMuted) const _CamOffPlaceholder(),
        ],
      );
    }
    return const _CamOffPlaceholder();
  }
}

class _CamOffPlaceholder extends StatelessWidget {
  const _CamOffPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Icon(Icons.videocam_off_outlined, color: AppColors.faint, size: 22),
      ),
    );
  }
}

class _NameTag extends StatelessWidget {
  const _NameTag({required this.track});

  final ParticipantTrack track;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (track.audioMuted)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.mic_off, size: 12, color: AppColors.dim),
            ),
          Text(
            track.isLocal ? '${track.name} (you)' : track.name,
            style: const TextStyle(color: AppColors.text, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Small mic/cam/device control bar — mute toggle, camera toggle, hide-self,
/// and a device picker. E5 docks this under/alongside [CameraGrid].
class MicCamControls extends ConsumerWidget {
  const MicCamControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lkState = ref.watch(livekitProvider);
    final notifier = ref.read(livekitProvider.notifier);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _ToggleIconButton(
          icon: lkState.micEnabled ? Icons.mic : Icons.mic_off,
          active: lkState.micEnabled,
          tooltip: lkState.micEnabled ? 'Mute microphone' : 'Unmute microphone',
          onTap: () => notifier.setMic(!lkState.micEnabled),
        ),
        _ToggleIconButton(
          icon: lkState.cameraEnabled ? Icons.videocam : Icons.videocam_off,
          active: lkState.cameraEnabled,
          tooltip: lkState.cameraEnabled ? 'Turn camera off' : 'Turn camera on',
          onTap: () => notifier.setCamera(!lkState.cameraEnabled),
        ),
        _ToggleIconButton(
          icon: lkState.hideSelf ? Icons.visibility_off : Icons.visibility,
          active: !lkState.hideSelf,
          tooltip: lkState.hideSelf ? 'Show my tile' : 'Hide my tile',
          onTap: () => notifier.setHideSelf(!lkState.hideSelf),
        ),
        _DevicePickerButton(notifier: notifier),
      ],
    );
  }
}

class _ToggleIconButton extends StatelessWidget {
  const _ToggleIconButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? AppColors.surface2 : AppColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line),
            ),
            child: Icon(icon, size: 18, color: active ? AppColors.text : AppColors.faint),
          ),
        ),
      ),
    );
  }
}

class _DevicePickerButton extends StatelessWidget {
  const _DevicePickerButton({required this.notifier});

  final LiveKitNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Choose devices',
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _openDevicePicker(context),
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line),
            ),
            child: const Icon(Icons.tune, size: 18, color: AppColors.faint),
          ),
        ),
      ),
    );
  }

  Future<void> _openDevicePicker(BuildContext context) async {
    final cameras = await notifier.cameraDevices();
    final mics = await notifier.microphoneDevices();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Camera', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
              for (final d in cameras)
                ListTile(
                  dense: true,
                  title: Text(d.label, style: const TextStyle(color: AppColors.text)),
                  onTap: () => notifier.selectCamera(d.deviceId),
                ),
              const SizedBox(height: AppSpacing.md),
              const Text('Microphone', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
              for (final d in mics)
                ListTile(
                  dense: true,
                  title: Text(d.label, style: const TextStyle(color: AppColors.text)),
                  onTap: () => notifier.selectMicrophone(d.deviceId),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
