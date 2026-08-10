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
import 'party_controls.dart';
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
  const PartyOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final party = ref.watch(partyProvider);
    final chatOpen = ref.watch(chatDrawerOpenProvider);
    final playerExpanded = ref.watch(
      nowPlayingProvider.select((playing) => playing.isExpanded),
    );
    final showDeviceRail =
        !playerExpanded || ref.watch(playerChromeVisibleProvider);

    return Stack(
      children: [
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
          // Your own mic, camera and hide-self, down the left edge.
          //
          // This rendered inside the deleted party route and was left mounted
          // NOWHERE — the controls existed, were reachable from no screen, and
          // a room had no way to mute itself. It belongs with the rest of the
          // room's chrome, at the root.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: IgnorePointer(
                ignoring: !showDeviceRail,
                child: AnimatedOpacity(
                  key: const Key('deviceRailVisibility'),
                  opacity: showDeviceRail ? 1 : 0,
                  duration: AppMotion.hover,
                  child: const DeviceRail(),
                ),
              ),
            ),
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

/// A solid, high-contrast room-chat card that grows from the right edge.
/// Artwork and video never show through it, so messages remain readable and
/// opening chat does not start a backdrop-capture loop.
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

class _ChatSlideOverState extends State<ChatSlideOver>
    with SingleTickerProviderStateMixin {
  final FocusNode _composer = FocusNode(debugLabel: 'chatComposer');

  static const double _collapsedWidth = 34;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    reverseDuration: const Duration(milliseconds: 240),
  );

  late final Animation<double> _extend = CurvedAnimation(
    parent: _c,
    curve: const Cubic(0.2, 0.82, 0.2, 1),
    reverseCurve: Curves.easeInCubic,
  );

  /// Content arrives after the surface has substantially formed. Fading text in
  /// during the stretch smears it, and reading a message that is still being
  /// squashed is worse than waiting 150ms for it.
  late final Animation<double> _contents = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.55, 1, curve: Curves.easeOut),
    reverseCurve: const Interval(0.7, 1, curve: Curves.easeIn),
  );

  @override
  void initState() {
    super.initState();
    // The composer is where the caret belongs for as long as the drawer is up:
    // a drawer you have to click into before typing costs two actions instead
    // of one. Re-asserted when the open animation settles, because focus can be
    // taken during it (the close button, a rebuild) and there is no other
    // moment that would put it back.
    _c.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.open) _grabFocus();
    });
    if (widget.open) {
      _c.value = 1;
      _grabFocus();
    }
  }

  @override
  void didUpdateWidget(ChatSlideOver old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    if (widget.open) {
      _c.forward();
      _grabFocus();
    } else {
      _c.reverse();
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
    _c.dispose();
    _composer.dispose();
    super.dispose();
  }

  /// Whether the caret is in a text field, and whether it has a selection.
  (bool editable, bool hasSelection) get _editableFocus {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return (false, false);
    final editor = focused.findAncestorStateOfType<EditableTextState>();
    if (editor == null) return (false, false);
    final selection = editor.textEditingValue.selection;
    return (true, selection.isValid && !selection.isCollapsed);
  }

  /// Ctrl/Cmd+C closes the drawer — including from inside the composer, which
  /// is where the caret always is when the drawer is open.
  ///
  /// The player's own handler cannot do this: once the composer has focus, the
  /// key event is delivered to the text field and never reaches the player's
  /// focus node, so the shortcut that OPENED chat could not close it. And the
  /// shared `shouldToggleChat` rule deliberately refuses while a text field has
  /// focus, to protect copy — correct for the player, wrong here, and not a
  /// rule to change underneath the web client.
  ///
  /// So the drawer answers for itself, with the copy guarantee intact: if there
  /// is a selection, Ctrl+C copies and the drawer stays. With nothing selected
  /// there is nothing to copy, and the keystroke means what the user meant.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.keyC) {
      return KeyEventResult.ignored;
    }
    final ctrlOrMeta =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!ctrlOrMeta) return KeyEventResult.ignored;
    final (_, hasSelection) = _editableFocus;
    if (hasSelection) return KeyEventResult.ignored; // copy wins
    widget.onClose();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _extend.value.clamp(0.0, 1.0);
        if (t <= 0.001) return const SizedBox.shrink();

        final width = _collapsedWidth + (widget.width - _collapsedWidth) * t;
        final wp = context.wp;

        return Positioned(
          // Clear of the window-chrome band. Running to the top edge put the
          // drawer's own header inside the strip macOS uses for dragging the
          // window, so the top-right of the title bar stopped responding
          // whenever chat was open.
          top: (Platform.isMacOS ? integratedDesktopChromeHeight : 0) + 12,
          bottom: 12,
          right: 12,
          width: width,
          child: SafeArea(
            left: false,
            child: Transform.translate(
              offset: Offset(18 * (1 - t), 0),
              child: DecoratedBox(
                key: const Key('chatSidebarCard'),
                decoration: BoxDecoration(
                  color: wp.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: wp.line2),
                  boxShadow: [
                    BoxShadow(
                      color: wp.shadow.withValues(alpha: 0.72),
                      blurRadius: 54,
                      spreadRadius: 2,
                      offset: const Offset(-14, 20),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(-4, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(21),
                  child: Opacity(
                    opacity: _contents.value.clamp(0.0, 1.0),
                    child: Focus(
                      onKeyEvent: _onKey,
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.escape):
                              widget.onClose,
                        },
                        child: _ChatBody(
                          composer: _composer,
                          onClose: widget.onClose,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ChatBody extends StatelessWidget {
  const _ChatBody({required this.composer, required this.onClose});

  final FocusNode composer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.wp.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.forum_outlined,
                  size: 17,
                  color: context.wp.text,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Room chat',
                      style: TextStyle(
                        color: context.wp.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Messages from this watch party',
                      style: TextStyle(color: context.wp.faint, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              AnalogIconButton(
                icon: Icons.close,
                tooltip: 'Close chat',
                onPressed: onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: context.wp.line),
          const SizedBox(height: 6),
          Expanded(child: ChatPanel(composerFocus: composer)),
        ],
      ),
    );
  }
}
