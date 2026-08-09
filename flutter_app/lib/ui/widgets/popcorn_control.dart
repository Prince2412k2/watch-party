import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../party/party_controls.dart';
import '../../state/state.dart';
import '../analog_tokens.dart';
import '../tokens.dart';
import 'wave_dots.dart';
import '../palette.dart';
import 'app_dialog.dart';
import 'avatar_view.dart';
import 'icon_tray.dart';
import 'join_code_dialog.dart';

/// The bottom-right watch-party control. A 46px popcorn button that expands an
/// [IconTray] of actions **upwards** out from above itself — the same object as
/// the profile control in the opposite corner, turned to suit the corner it is
/// in. Sideways from here would run the tray along the bottom edge, into the
/// nav; up is the only direction with clear air in it.
///
/// It carries a green live dot while a session is active and a red badge
/// counting guests awaiting approval; the tray auto-opens for a host the moment
/// someone is waiting, and a tap outside closes it via [TapRegion].
///
/// The popcorn glyph is intentionally always dark (`#202126`) regardless of
/// theme — it is a fixed brand mark, not a theme surface.
///
/// ## What the tray offers, by state
///
/// Listed top to bottom, which is the order they stack above the button.
///
/// | State | Actions |
/// | --- | --- |
/// | No party | start ¦ join with a code |
/// | Host | end · copy invite ¦ return |
/// | Guest | leave ¦ return |
///
/// The three actions after the divider are not decoration and are not padding:
/// **join** is the only way a guest ever gets into a room, **return** is the
/// only way back after the party screen's Back minimises it, and the **approve
/// / reject** chips that appear while someone is waiting are the only way a
/// host lets anybody in. Removing them would not simplify the control, it would
/// break the feature.
///
/// What the 320px panel had and this does not: the QR code, the printed room
/// code, the roster, and the "watch together" blurb. Copy-invite carries the
/// invite; the roster is visible on the party screen itself.
class PopcornControl extends ConsumerStatefulWidget {
  const PopcornControl({super.key});

  @override
  ConsumerState<PopcornControl> createState() => _PopcornControlState();
}

class _PopcornControlState extends ConsumerState<PopcornControl>
    with TickerProviderStateMixin {
  /// Dialogs open on the ordinary context: the chrome sits inside its own
  /// Navigator now (see app.dart), so there is one directly above this.
  /// Built in [initState], not as a `late final` initializer, and vsynced by
  /// the plural mixin.
  ///
  /// A lazy `late final` here crashed on every tap: the first thing to touch
  /// the field was `onTapOutside`, and after a hot reload the field is reset
  /// while the ticker the State already handed out is not — so
  /// `SingleTickerProviderStateMixin` asserts on the second one. Deterministic
  /// creation plus a provider that tolerates more than one ticker fixes both
  /// halves of that.
  late final AnimationController _tray;

  bool _busy = false;
  bool _copied = false;

  /// A failure has nowhere to print now that the panel's error line is gone, so
  /// it rides on the tooltip of the action that caused it and tints that button
  /// red. The server's wording still reaches the user, just on demand.
  ///
  /// Only "start a party" can fail on this tray today; the rest are local or
  /// already have their own surface. Without this, a refused create would leave
  /// the button doing visibly nothing.
  String? _error;

  bool get _open => _tray.value > 0;

  PartyNotifier get _party => ref.read(partyProvider.notifier);

  @override
  void initState() {
    super.initState();
    _tray = AnimationController(
      vsync: this,
      duration: AnalogMotion.drawerMs,
      reverseDuration: AnalogMotion.exitMs,
    );
  }

  @override
  void dispose() {
    _tray.dispose();
    super.dispose();
  }

  void _close() {
    if (_open) _tray.reverse();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Start a room.
  ///
  /// If something is already playing, the room starts ON it, carrying the live
  /// position — the "start a party mid-movie" affordance that used to be a
  /// button floated over the solo player. That button had nowhere to live once
  /// the player stopped being a screen, and it belongs here anyway: starting a
  /// room is a popcorn action wherever you are.
  Future<void> _start() => _guard(() async {
    final now = ref.read(nowPlayingProvider);
    final itemId = now.itemId;
    if (itemId == null) {
      await _party.create();
      return;
    }
    await _party.createFromCurrentPlayback(
      mediaItemId: itemId,
      position: ref.read(playerControllerProvider).positionNow,
      audioStreamIndex: now.audioStreamIndex,
      subtitleStreamIndex: now.subtitleStreamIndex,
    );
  });

  Future<void> _join() async {
    setState(() => _error = null);
    await showDialog<String>(
      context: context,
      builder: (_) => JoinCodeDialog(onJoin: (code) => _party.join(code)),
    );
    // The shell opens the player when the approved room enters watching.
  }

  Future<void> _end() async {
    _close();
    final ok = await showConfirm(
      context,
      title: 'End this party?',
      body: 'The room closes for everyone.',
      confirmLabel: 'End party',
      danger: true,
    );
    if (ok) await _guard(() => _party.end());
  }

  Future<void> _leave() async {
    _close();
    await _guard(() => _party.leave());
  }

  void _copyInvite(String joinUrl) {
    Clipboard.setData(ClipboardData(text: joinUrl));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(partyWaitingProvider, (_, next) {
      if (next.isNotEmpty && !_open && _party.isHost) _tray.forward();
    });

    final session = ref.watch(partyProvider);
    final waiting = ref.watch(partyWaitingProvider);
    final isHost = session != null && _party.isHost;
    // Asked to join, not yet let in. The tray is the only surface that can say
    // so since the waiting room was deleted with its route.
    final pending = session == null && ref.watch(partyPendingProvider) != null;

    return TapRegion(
      onTapOutside: (_) => _close(),
      // Upwards, not sideways: this control sits in the bottom-right corner, so
      // a tray running left would lie along the bottom edge in the nav's lap.
      // Up is the only direction here with clear air in it.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTray(
            animation: _tray,
            axis: Axis.vertical,
            children: [
              ..._actions(session, isHost, pending),
              // Guests waiting on the door. Transient, host-only, and the whole
              // reason the tray auto-opens.
              if (isHost && waiting.isNotEmpty) ...[
                const TrayDivider(),
                for (final p in waiting.take(2)) ...[
                  _WaitingFace(userId: p.userId, name: p.name),
                  TrayButton(
                    icon: Icons.close,
                    tooltip: 'Reject ${p.name}',
                    tint: kSemanticRed,
                    onTap: () => _party.reject(p.userId),
                  ),
                  TrayButton(
                    icon: Icons.check,
                    tooltip: 'Approve ${p.name}',
                    tint: kPartyLive,
                    onTap: () => _party.approve(p.userId),
                  ),
                ],
              ],
            ],
          ),
          _PopcornButton(
            live: session != null,
            pending: pending,
            waiting: waiting.length,
            onTap: () => _open ? _tray.reverse() : _tray.forward(),
          ),
        ],
      ),
    );
  }

  /// The listed actions, in the order they were asked for: left to right, with
  /// the destructive one furthest from the handle in every state.
  List<Widget> _actions(PartyState? session, bool isHost, bool pending) {
    // Back on the film MINIMISES it to a tile — the room keeps running — so
    // there has to be a non-destructive way back to full screen, or minimising
    // strands the user next to a live session. It used to navigate to
    // `/party/:id`; now it just expands the player that is already playing.
    final minimised =
        session != null &&
        session.stage == 'watching' &&
        ref.watch(nowPlayingProvider).isFloating;
    final returnAction = minimised
        ? [
            const TrayDivider(),
            TrayButton(
              key: const Key('returnToPartyButton'),
              icon: Icons.open_in_full,
              tooltip: 'Back to full screen',
              onTap: ref.read(nowPlayingProvider.notifier).expand,
            ),
          ]
        : const <Widget>[];

    // The Watch Party panel — roster, transfer, kick, sync mode, switch movie.
    // It used to open on a right-click over the party route's stage, which
    // means it went unreachable the moment that route did. It belongs here
    // anyway: the popcorn is on every screen, and this is the room's menu.
    final panelAction = session == null
        ? const <Widget>[]
        : [
            TrayButton(
              key: const Key('partyControlsButton'),
              icon: Icons.tune,
              tooltip: 'Watch party controls',
              onTap: () => showDialog<void>(
                context: context,
                barrierColor: const Color(0xB8000000),
                builder: (_) => const HostControlsDialog(),
              ),
            ),
          ];

    // Waiting on the host's answer. Neither "start a party" nor "join with a
    // code" is true here, and offering them would invite you to ask twice.
    if (pending) {
      return [
        TrayButton(
          key: const Key('cancelJoinRequestButton'),
          icon: Icons.close,
          tooltip: 'Stop waiting',
          tint: kSemanticRed,
          onTap: () => _guard(() => _party.leave()),
        ),
      ];
    }

    if (session == null) {
      return [
        TrayButton(
          icon: _error != null ? Icons.error_outline : Icons.add,
          tooltip: _error ?? 'Start a watch party',
          tint: _error != null ? kSemanticRed : null,
          busy: _busy,
          onTap: _start,
        ),
        const TrayDivider(),
        TrayButton(
          // A keypad, because the action is "type the code someone sent you".
          // This was Icons.login — the arrow-into-a-door sign-in glyph — which
          // in an app that HAS an account to sign into read as exactly that,
          // and sat a few pixels from the profile tray's Icons.logout meaning
          // the real thing. A text-free tray only works if each glyph names its
          // own action; this one named a different feature entirely.
          icon: Icons.dialpad,
          tooltip: 'Join with a code',
          onTap: _join,
        ),
      ];
    }

    if (isHost) {
      return [
        TrayButton(
          icon: Icons.stop_circle_outlined,
          tooltip: 'End the party',
          tint: kSemanticRed,
          busy: _busy,
          onTap: _end,
        ),
        TrayButton(
          icon: _copied ? Icons.check : Icons.link,
          tooltip: _copied ? 'Invite copied' : 'Copy the invite link',
          onTap: () => _copyInvite(
            '${ref.read(apiClientProvider).baseUrl}/party/${session.id}',
          ),
        ),
        ...panelAction,
        ...returnAction,
      ];
    }

    return [
      TrayButton(
        // Leaving a room is not signing out, and this used the same door-arrow
        // as the profile tray's Sign out — sitting in the opposite corner of
        // the same screen, at the same size, with no text on either. Pressing
        // the wrong one ends your session in the middle of a film.
        icon: Icons.group_remove,
        tooltip: 'Leave the party',
        tint: kSemanticRed,
        busy: _busy,
        onTap: _leave,
      ),
      ...panelAction,
      ...returnAction,
    ];
  }

}

/// A face in the tray, so approving somebody is approving a person rather than
/// a tick next to nothing.
class _WaitingFace extends StatelessWidget {
  const _WaitingFace({required this.userId, required this.name});

  final String userId;
  final String name;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '$name wants to join',
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: AvatarView(userId: userId, name: name, size: 36),
    ),
  );
}

class _PopcornButton extends StatefulWidget {
  const _PopcornButton({
    required this.live,
    required this.pending,
    required this.waiting,
    required this.onTap,
  });

  final bool live;

  /// Asked to join and waiting on the host. Shown as a breathing ring rather
  /// than the live dot: you are not in the room yet, and a steady green dot
  /// would say you were.
  final bool pending;

  final int waiting;
  final VoidCallback onTap;

  /// The handle. A shade larger than the tray it opens, because it is the thing
  /// you look for when nothing is open and the tray is the thing you look at
  /// once it is.
  static const double _size = 69;

  @override
  State<_PopcornButton> createState() => _PopcornButtonState();
}

class _PopcornButtonState extends State<_PopcornButton> {
  bool _hover = false;

  // No controller here any more. WaveDots owns its own ticker and is mounted
  // only while pending, which keeps the same bound this class used to enforce
  // by hand: the popcorn is on every screen, so a ticker that ran here
  // unconditionally would mean `pumpAndSettle` never returns in any test that
  // renders the shell.

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          width: _PopcornButton._size,
          height: _PopcornButton._size,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFF2A2C31) : const Color(0xFF202126),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x38000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Image.asset('assets/popcorn.png', width: 51, height: 51),
              if (widget.pending)
                // Waiting on the host, shown where the live dot would be. Wave
                // dots rather than a ring or a static pip: the request is in
                // flight and has not failed, which is the only thing anyone
                // wants to know while waiting, and a motionless mark says
                // nothing about either.
                //
                // Neutral, not green: green is the live dot and means you are
                // IN. Waiting has no colour in the palette, and inventing one
                // to say "almost" would add a semantic token for a transient
                // state.
                Positioned(
                  right: -2,
                  bottom: -1,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xE617181B),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppColors.line2),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        child: WaveDots(
                          color: AppColors.text,
                          dotSize: 3.5,
                          amplitude: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.live)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: kPartyLive,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF202126),
                        width: 3,
                      ),
                    ),
                  ),
                ),
              if (widget.waiting > 0)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 27,
                      minHeight: 27,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kSemanticRed,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${widget.waiting}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
