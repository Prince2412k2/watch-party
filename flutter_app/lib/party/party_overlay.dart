// The room's chrome, mounted above the router.
//
// Cameras, chat, join requests and the A/V error banner used to render inside
// `PartyScreen`, which meant they existed only while you were standing on
// `/party/:id`. That is the wrong lifetime for all four: a room outlives any
// one screen, and the whole point of ambient rooms is that you keep using your
// app while you are in one. Being in a room should follow you around the app,
// not be a place you have to stay.
//
// So these move next to [PlayerHost], for the same reason it lives there. This
// widget renders nothing at all when there is no party, which is what makes it
// safe to mount unconditionally at the root.
//
// One thing deliberately did NOT come along: the docked camera column. It only
// made sense when the party stage was the whole window and the cameras could
// take a strip off its left edge. Over an app you are using, a column pinned to
// the left edge is just something covering your library, so the cameras float —
// draggable, snappable tiles, the same treatment the movie tile gets.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analog/chrome/chrome.dart';
import '../models/models.dart';
import '../state/state.dart';
import '../ui/analog_tokens.dart';
import '../ui/ui.dart';
import '../ui/widgets/floating_camera_tile.dart';

/// The chat drawer's width. It overlays whatever is underneath rather than
/// narrowing it, so this is only ever an inset for things that must stay clear.
const double kChatDrawerWidth = 360;

/// Everything a room puts on screen that is not the player itself.
///
/// Layered to match the old party stack's z-order, minus the stage: cameras,
/// then the two notification layers (join requests, A/V errors — never faded,
/// never auto-hidden), then chat on top.
class PartyOverlay extends ConsumerWidget {
  const PartyOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider);
    final chatOpen = ref.watch(chatDrawerOpenProvider);

    return Stack(
      children: [
        Positioned.fill(child: child),
        if (party != null) ...[
          // Cameras keep clear of the drawer by insetting their layer, so a
          // tile can neither hide under chat nor straddle its border. Nothing
          // else moves when chat opens.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            left: 0,
            top: 0,
            bottom: 0,
            right: chatOpen ? kChatDrawerWidth : 0.0,
            child: const FloatingCameraLayer(),
          ),
          const Positioned(top: 64, right: 12, child: JoinRequestsLayer()),
          const Positioned(
            top: 70,
            left: 0,
            right: 0,
            child: LiveKitErrorBanner(),
          ),
          ChatSlideOver(
            open: chatOpen,
            width: kChatDrawerWidth,
            onClose: () =>
                ref.read(chatDrawerOpenProvider.notifier).state = false,
          ),
        ],
      ],
    );
  }
}

/// Host-only "wants to join" notification, kept visible independent of the
/// auto-hide chrome (a notification, per the design guide). Renders nothing for
/// guests or when no one is waiting.
class JoinRequestsLayer extends ConsumerWidget {
  const JoinRequestsLayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider);
    final me = ref.watch(currentUserIdProvider);
    final isHost = party != null && me != null && party.hostId == me;
    final waiting = ref.watch(partyWaitingProvider);
    if (!isHost || waiting.isEmpty) return const SizedBox.shrink();
    return SafeArea(child: _JoinRequests(waiting: waiting));
  }
}

/// The LiveKit A/V error banner — opaque and always visible (a notification),
/// not tied to the auto-hide chrome.
class LiveKitErrorBanner extends ConsumerWidget {
  const LiveKitErrorBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final error = ref.watch(livekitProvider.select((s) => s.error));
    if (error == null) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: AnalogPanel(
                translucent: true,
                blur: AppBlur.overlay,
                lift: AnalogLift.over,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: AppColors.red,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        error,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Host-only "wants to join" card.
///
/// It used to be a titled panel with a rule under the heading and a row per
/// person: a name in a list, and two icon buttons beside it. That is a settings
/// table, and it read as one — nothing about it said a PERSON was standing at
/// the door, which is the only thing this notice is about.
///
/// So it leads with the face, the way the toast rail and the popcorn tray
/// already do, on the same glass the chat drawer is made of. Approve and reject
/// are the same two glyphs in the same two colours as their counterparts in the
/// tray, because they are the same two actions and a host should not have to
/// learn them twice.
class _JoinRequests extends ConsumerWidget {
  const _JoinRequests({required this.waiting});
  final List<Participant> waiting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Reveal(
      child: SizedBox(
        width: 292,
        child: LiquidGlass(
          opaque: MediaQuery.of(context).highContrast,
          borderRadius: BorderRadius.circular(AnalogRadius.cardPx + 4),
          blur: AppBlur.overlay,
          shadow: const [
            BoxShadow(
              color: Color(0x59000000),
              blurRadius: 28,
              offset: Offset(0, 10),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final w in waiting) _JoinRequestRow(participant: w),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One person at the door: their face, their name, and the two answers.
class _JoinRequestRow extends ConsumerWidget {
  const _JoinRequestRow({required this.participant});

  final Participant participant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(partyProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          AvatarView(
            userId: participant.userId,
            name: participant.name,
            size: 38,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  participant.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                // Under the name, not as a panel heading: it describes this
                // person, and there is no longer a list for a heading to head.
                const Text(
                  'wants to join',
                  style: TextStyle(
                    color: AppColors.faint,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          AnalogIconButton(
            icon: Icons.close,
            tooltip: 'Reject ${participant.name}',
            color: AppColors.red,
            onPressed: () => notifier.reject(participant.userId),
          ),
          AnalogIconButton(
            icon: Icons.check,
            tooltip: 'Approve ${participant.name}',
            color: AppColors.green,
            onPressed: () => notifier.approve(participant.userId),
          ),
        ],
      ),
    );
  }
}

/// The room chat, as a glass panel over everything.
///
/// It is an overlay in the strict sense: nothing else reads its width, so
/// opening it changes no other widget's constraints and neither the video nor
/// the app underneath resizes or reflows. What used to happen — the stage
/// narrowing by 360px — reframed the entire movie every time someone wanted to
/// type.
///
/// Opening it moves keyboard focus into the composer, and closing it hands
/// focus back so the player's keymap (space, arrows, F) works again without a
/// click. A drawer you have to click into before typing is a drawer that costs
/// two actions instead of one.
class ChatSlideOver extends StatefulWidget {
  const ChatSlideOver({
    super.key,
    required this.open,
    required this.width,
    required this.onClose,
  });

  final bool open;
  final double width;
  final VoidCallback onClose;

  @override
  State<ChatSlideOver> createState() => _ChatSlideOverState();
}

class _ChatSlideOverState extends State<ChatSlideOver> {
  final FocusNode _composer = FocusNode(debugLabel: 'chatComposer');

  @override
  void initState() {
    super.initState();
    if (widget.open) _grabFocus();
  }

  @override
  void didUpdateWidget(ChatSlideOver old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.open) {
      _grabFocus();
    } else {
      // Give focus back to whatever the player put it on. unfocus() alone
      // would leave the tree with no primary focus and swallow the next key.
      _composer.unfocus();
    }
  }

  /// Focus after the frame that opens the drawer. Requesting it during build
  /// targets a node that is still parked off-screen, and the request is
  /// dropped.
  void _grabFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.open) _composer.requestFocus();
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.open;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      // Clear of the window-chrome band. Running to the top edge put the
      // drawer's own header inside the strip macOS uses for dragging the
      // window, so the top-right of the title bar stopped responding whenever
      // chat was open — and the panel's heading sat level with the traffic
      // lights, reading as part of the title bar rather than as content.
      top: Platform.isMacOS ? integratedDesktopChromeHeight : 0,
      bottom: 0,
      right: open ? 0 : -(widget.width + 12),
      width: widget.width,
      child: SafeArea(
        left: false,
        // Escape closes. With the cursor parked in the composer the player's
        // own keymap no longer sees anything typed here, so without this the
        // drawer would be a place you can get into from the keyboard and only
        // out of with the mouse.
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
          },
          child: LiquidGlass(
            opaque: MediaQuery.of(context).highContrast,
            // Square against the right edge, rounded on the side that faces the
            // picture — the panel reads as something laid ON the stage rather
            // than a slot cut out of it.
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AnalogRadius.cardPx + 6),
              bottomLeft: Radius.circular(AnalogRadius.cardPx + 6),
            ),
            blur: 24,
            shadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 34,
                offset: Offset(-10, 0),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ROOM CHAT',
                              style: TextStyle(
                                fontFamily: AppFonts.mono,
                                color: AppColors.faint,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Conversation',
                              style: TextStyle(
                                color: AppColors.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnalogIconButton(
                        icon: Icons.close,
                        tooltip: 'Close chat',
                        onPressed: widget.onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(child: ChatPanel(composerFocus: _composer)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
