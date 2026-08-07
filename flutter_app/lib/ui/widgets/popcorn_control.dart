import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../state/state.dart';
import '../analog_tokens.dart';
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
/// | No party | start · shared browser ¦ join with a code |
/// | Host | end · copy invite · shared browser ¦ return |
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _tray = AnimationController(
    vsync: this,
    duration: AnalogMotion.drawerMs,
    reverseDuration: AnalogMotion.exitMs,
  );

  bool _busy = false;
  bool _copied = false;

  /// A failure has nowhere to print now that the panel's error line is gone, so
  /// it rides on the tooltip of the button that caused it and tints that button
  /// red. The server's wording — "the shared browser is in use right now" —
  /// still reaches the user, just on demand.
  String? _error;

  bool get _open => _tray.value > 0;

  PartyNotifier get _party => ref.read(partyProvider.notifier);

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

  Future<void> _start() => _guard(() => _party.create());

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

  /// Open or close the party's shared browser.
  ///
  /// With no session there is nothing to share a browser *with*, so this starts
  /// the party first. "Browse together" is one intent, not two steps, and
  /// making the user start a room before the button lights up would be asking
  /// them to do the app's bookkeeping.
  Future<void> _sharedBrowser() => _guard(() async {
    final session = ref.read(partyProvider);
    if (session == null) {
      await _party.create();
      await _party.startSharedBrowser();
      return;
    }
    if (session.stage == 'browser') {
      await _party.stopSharedBrowser();
    } else {
      await _party.startSharedBrowser();
    }
  });

  @override
  Widget build(BuildContext context) {
    ref.listen(partyWaitingProvider, (_, next) {
      if (next.isNotEmpty && !_open && _party.isHost) _tray.forward();
    });

    final session = ref.watch(partyProvider);
    final waiting = ref.watch(partyWaitingProvider);
    final isHost = session != null && _party.isHost;

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
              ..._actions(session, isHost),
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
            waiting: waiting.length,
            onTap: () => _open ? _tray.reverse() : _tray.forward(),
          ),
        ],
      ),
    );
  }

  /// The listed actions, in the order they were asked for: left to right, with
  /// the destructive one furthest from the handle in every state.
  List<Widget> _actions(PartyState? session, bool isHost) {
    final browserAvailable = ref.watch(sharedBrowserProvider).available;
    // The party surface's Back MINIMISES — the room keeps running without a
    // window on it — so there has to be a non-destructive way back, or
    // minimising strands the user next to a live session.
    final onImmersiveStage =
        session != null &&
        (session.stage == 'watching' || session.stage == 'browser');
    final returnAction = onImmersiveStage
        ? [
            const TrayDivider(),
            TrayButton(
              key: const Key('returnToPartyButton'),
              icon: Icons.open_in_full,
              tooltip: 'Return to the party',
              onTap: () => context.go('/party/${session.id}'),
            ),
          ]
        : const <Widget>[];

    if (session == null) {
      return [
        TrayButton(
          icon: Icons.add,
          tooltip: 'Start a watch party',
          busy: _busy,
          onTap: _start,
        ),
        // Shown unconditionally here, unlike the host case: `available` is
        // reported by a live room, and out of a party there is no room to
        // report it. Hiding the button until you already have one would mean
        // it never appears in the state where it is most useful. A server
        // without the feature answers with an error, which lands on the
        // button's own tooltip.
        _browserButton(null),
        const TrayDivider(),
        TrayButton(
          icon: Icons.login,
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
        if (browserAvailable) _browserButton(session),
        ...returnAction,
      ];
    }

    return [
      TrayButton(
        icon: Icons.logout,
        tooltip: 'Leave the party',
        tint: kSemanticRed,
        busy: _busy,
        onTap: _leave,
      ),
      ...returnAction,
    ];
  }

  Widget _browserButton(PartyState? session) {
    final open = session?.stage == 'browser';
    final failed = _error != null;
    return TrayButton(
      icon: open ? Icons.public_off : Icons.public,
      tooltip: failed
          ? _error!
          : open
          ? 'Close the shared browser'
          : 'Browse together',
      tint: failed ? kSemanticRed : null,
      busy: _busy,
      onTap: _sharedBrowser,
    );
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
      padding: const EdgeInsets.only(left: 4, right: 2),
      child: AvatarView(userId: userId, name: name, size: 24),
    ),
  );
}

class _PopcornButton extends StatefulWidget {
  const _PopcornButton({
    required this.live,
    required this.waiting,
    required this.onTap,
  });

  final bool live;
  final int waiting;
  final VoidCallback onTap;

  @override
  State<_PopcornButton> createState() => _PopcornButtonState();
}

class _PopcornButtonState extends State<_PopcornButton> {
  bool _hover = false;

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
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          width: 46,
          height: 46,
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
              Image.asset('assets/popcorn.png', width: 34, height: 34),
              if (widget.live)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: kPartyLive,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF202126),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              if (widget.waiting > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kSemanticRed,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${widget.waiting}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
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
