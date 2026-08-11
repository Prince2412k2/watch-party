// Chat message toasts over the player.
//
// "New messages can appear over the player as compact toasts. They disappear
// without requiring dismissal and must not cover subtitles, transport
// controls, participant faces, or the chat toggle."
// (docs/watchparty-design/player-interface-reference.md)
//
// Solid, not semi-transparent: these sit over moving picture, and a bright
// frame behind a frosted plate put video straight through the words.
//
// The queue, the three-deep stack, the collapsed count and the four second
// lifetime all live in analog/player_core.dart, shared byte-for-byte with the
// React player. This widget only draws a [ToastView].

import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';
import '../chrome/analog_toast.dart' show AnalogToastSurface;
import '../player_core.dart';

class AnalogToastStack extends StatelessWidget {
  const AnalogToastStack({
    super.key,
    required this.view,
    this.avatarBuilder,
    this.maxWidth = 300,
  });

  final ToastView view;

  /// Draws the sender's face. Supplied by the caller rather than built here so
  /// this layer stays free of the providers an avatar needs — the same split
  /// the app-wide rail makes with its `leading` widget. Null draws no face.
  final Widget Function(String userId, String name)? avatarBuilder;

  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (view.toasts.isEmpty && view.collapsedCount == 0) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (view.collapsedCount > 0)
              AnalogToastSurface(
                child: Text(
                  '+${view.collapsedCount} earlier '
                  '${view.collapsedCount == 1 ? 'message' : 'messages'}',
                  style: const TextStyle(
                    color: AnalogColor.inkDim,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            for (final toast in view.toasts)
              _ChatToast(
                key: ValueKey(toast.id),
                toast: toast,
                avatarBuilder: avatarBuilder,
                animate: !media.disableAnimations,
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatToast extends StatelessWidget {
  const _ChatToast({
    super.key,
    required this.toast,
    required this.avatarBuilder,
    required this.animate,
  });

  final ToastMessage toast;
  final Widget Function(String userId, String name)? avatarBuilder;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    // liveRegion announces the message where it stands. ExcludeFocus keeps the
    // announcement from pulling keyboard focus off whatever the viewer is
    // using — "announced accessibly without moving keyboard focus".
    final surface = ExcludeFocus(
      child: Semantics(
        liveRegion: true,
        label: '${toast.sender} says ${toast.preview}',
        excludeSemantics: true,
        child: AnalogToastSurface(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (avatarBuilder != null) ...[
                avatarBuilder!(toast.userId, toast.sender),
                const SizedBox(width: AnalogSpace.smPx),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      toast.sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AnalogColor.inkDim,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      toast.preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AnalogColor.ink,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!animate) return surface;
    return TweenAnimationBuilder<double>(
      key: ValueKey('fade-${toast.id}'),
      tween: Tween(begin: 0, end: 1),
      duration: AnalogMotion.chromeFadeMs,
      curve: AnalogMotion.chromeFadeEase,
      builder: (context, value, child) =>
          Opacity(opacity: value, child: child),
      child: surface,
    );
  }
}
