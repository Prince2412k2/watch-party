// The room's controls: the Watch Party panel, device rail, and their pieces.
//
// These lived in `party_screen.dart`, reachable only by right-clicking the
// party route's stage. The route is gone, so they hang off the popcorn instead
// -- which is where a control you reach for mid-film belongs anyway, and which
// is present on every screen rather than one.
//
// Nothing here changed except its address and its privacy: the names the
// popcorn has to call are public now.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analog/chrome/chrome.dart';
import '../models/models.dart';
import '../state/state.dart';
import '../ui/analog_tokens.dart';
import '../ui/ui.dart';

/// A flat, boxless, monochrome player-chrome icon button (`Player.tsx`
/// `IconBtn`): no box/border/fill; glyph rests at 62% near-white, brightens to
/// full near-white on hover / when [active], and is red when [danger].
///
class _AvIconButton extends StatefulWidget {
  const _AvIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;
  final bool busy;

  static const Color _rest = Color(0x9EF4F4F5); // rgba(244,244,245,.62)
  static const Color _bright = Color(0xFFF4F4F5);
  static const Color _danger = Color(0xFFE0655E);

  @override
  State<_AvIconButton> createState() => _AvIconButtonState();
}

class _AvIconButtonState extends State<_AvIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.danger
        ? _AvIconButton._danger
        : ((widget.active || _hover)
              ? _AvIconButton._bright
              : _AvIconButton._rest);

    final Widget glyph = widget.busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _AvIconButton._rest,
            ),
          )
        : Icon(widget.icon, size: 19, color: color);

    return AnalogTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.busy ? null : widget.onTap,
          child: SizedBox(width: 34, height: 34, child: Center(child: glyph)),
        ),
      ),
    );
  }
}

/// Mic/camera toggle that shows a pending spinner while the (slow, native)
/// LiveKit publish future is in flight, and reads danger (red) while OFF —
/// matching the web `IconBtn danger={!micOn}`.
class _AvPendingToggle extends StatefulWidget {
  const _AvPendingToggle({
    required this.iconOn,
    required this.iconOff,
    required this.on,
    required this.tooltip,
    required this.onToggle,
  });

  final IconData iconOn;
  final IconData iconOff;
  final bool on;
  final String tooltip;
  final Future<void> Function() onToggle;

  @override
  State<_AvPendingToggle> createState() => _AvPendingToggleState();
}

class _AvPendingToggleState extends State<_AvPendingToggle> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onToggle();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AvIconButton(
      icon: widget.on ? widget.iconOn : widget.iconOff,
      tooltip: widget.tooltip,
      danger: !widget.on,
      busy: _busy,
      onTap: _run,
    );
  }
}

/// The Watch Party control panel, opened by right-click / long-press over the
/// stage.
///
/// Rebuilt on the tray principle the rest of the app moved to: a face for each
/// person, a glyph for each action, and no prose. What it replaced was a 540px
/// scrolling column of section headings, explanatory sentences, labelled
/// buttons and a QR block — a settings page rendered over a film.
///
/// What survived the cut and why:
///
/// * **Faces, not a roster.** Avatars carry identity better than a list of
///   names, and the host's is ringed rather than captioned. Host actions
///   (transfer, remove) hang off a right-click on the face itself, which is
///   where you would aim anyway.
/// * **No QR.** It cost the most space of anything here and answered a question
///   nobody asks from inside a running party — you invite people before you
///   start watching, and copy-link does that in one press from any device.
/// * **The code stays.** It is data, not chrome: the one thing you read aloud
///   to someone sitting next to you.
///
/// Everything is gated by role, and the two destructive actions (end the party,
/// remove someone) keep their confirmation and their red.
class HostControlsDialog extends ConsumerStatefulWidget {
  const HostControlsDialog({super.key});

  @override
  ConsumerState<HostControlsDialog> createState() => _HostControlsDialogState();
}

class _HostControlsDialogState extends ConsumerState<HostControlsDialog> {
  bool _copied = false;
  bool _refreshing = false;
  bool _ending = false;

  Future<void> _copyInvite(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copied = true);
    // The glyph itself is the receipt, so no toast: a panel this small should
    // not raise a notice over the top of itself.
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Rebuild this client's A/V room. Host and guest alike — a wedged publish
  /// path is not a role-specific fault, and the host having to end the party to
  /// clear one was the worst version of this.
  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final error = await ref.read(partyProvider.notifier).reconnectAv();
    if (!mounted) return;
    setState(() => _refreshing = false);
    showAnalogToast(
      context,
      error == null ? 'Video reconnected' : 'Could not reconnect video',
      tone: error == null ? AnalogToastTone.success : AnalogToastTone.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final party = ref.watch(partyProvider);
    if (party == null) return const SizedBox.shrink();
    final me = ref.watch(currentUserIdProvider);
    final isHost = me != null && party.hostId == me;
    final notifier = ref.read(partyProvider.notifier);
    final joinUrl = '${ref.watch(apiClientProvider).baseUrl}/party/${party.id}';

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 336),
        child: LiquidGlass(
          opaque: MediaQuery.of(context).highContrast,
          borderRadius: BorderRadius.circular(AnalogRadius.cardPx + 6),
          blur: 24,
          shadow: const [
            BoxShadow(
              color: Color(0x8C000000),
              blurRadius: 40,
              offset: Offset(0, 14),
            ),
          ],
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PartyFaces(party: party, isHost: isHost, notifier: notifier),
              const SizedBox(height: AppSpacing.md),
              Divider(height: 1, color: wp.line),
              const SizedBox(height: AppSpacing.md),

              // Everyone's actions, then the host's. One wrapping row so the
              // panel grows by a line rather than by a section.
              Wrap(
                spacing: 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _AvIconButton(
                    icon: _refreshing ? Icons.hourglass_empty : Icons.refresh,
                    tooltip: _refreshing
                        ? 'Reconnecting…'
                        : 'Reconnect my video and audio',
                    onTap: _refreshing ? null : _refresh,
                  ),
                  _AvIconButton(
                    icon: _copied ? Icons.check : Icons.link,
                    tooltip: _copied ? 'Invite copied' : 'Copy the invite link',
                    onTap: () => _copyInvite(joinUrl),
                  ),
                  if (isHost) ...[
                    const _AvDivider.vertical(),
                    _AvIconButton(
                      icon: Icons.stop_circle_outlined,
                      tooltip: 'End the party for everyone',
                      danger: true,
                      busy: _ending,
                      onTap: _ending ? null : () => _end(notifier),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: AppSpacing.md),
              // The code: data, not a label, so it keeps its own line and its
              // own weight. Selectable because reading it out is half of what
              // it is for.
              SelectableText(
                party.id,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  color: wp.dim,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _end(PartyNotifier notifier) async {
    final ok = await showConfirm(
      context,
      title: 'End party for everyone?',
      body:
          'Everyone will be disconnected and returned to the lobby. This can\'t be undone.',
      confirmLabel: 'End party',
      danger: true,
    );
    if (!ok) return;
    if (mounted) setState(() => _ending = true);
    try {
      await notifier.end();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      showAnalogToast(
        context,
        'The party closed here, but the server did not confirm it.',
        tone: AnalogToastTone.warning,
      );
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }
}

/// A named switch: a mode you set and leave, as opposed to a button you press.
///
/// The hint is one line and it changes with the state, so it reports what is
/// true rather than explaining the feature.
/// The room, as faces.
///
/// The host's avatar is ringed — a mark on the face itself rather than a badge
/// beside a name, because at this size the face IS the row. Right-clicking a
/// guest's face gives the host transfer and remove; on a guest's own screen the
/// faces are just faces.
class _PartyFaces extends StatelessWidget {
  const _PartyFaces({
    required this.party,
    required this.isHost,
    required this.notifier,
  });

  final PartyState party;
  final bool isHost;
  final PartyNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final p in party.participants)
          _Face(
            key: ValueKey(p.userId),
            participant: p,
            actionable: isHost && !p.isHost,
            notifier: notifier,
          ),
      ],
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    super.key,
    required this.participant,
    required this.actionable,
    required this.notifier,
  });

  final Participant participant;
  final bool actionable;
  final PartyNotifier notifier;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final p = participant;

    final face = Tooltip(
      message: p.isHost ? '${p.name} · host' : p.name,
      child: Container(
        width: _size + 6,
        height: _size + 6,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Uniform, always: a non-uniform border on a circle throws every
          // frame, so the ring is drawn at full width and merely made
          // transparent when this is not the host.
          border: Border.all(
            color: p.isHost ? wp.text : Colors.transparent,
            width: 2,
          ),
        ),
        child: Center(
          child: AvatarView(userId: p.userId, name: p.name, size: _size),
        ),
      ),
    );

    if (!actionable) return face;

    return AnalogContextMenu(
      actions: [
        AnalogMenuAction(
          label: 'Make host',
          icon: Icons.swap_horiz,
          onSelected: () => notifier.transferHost(p.userId),
        ),
        AnalogMenuAction(
          label: 'Remove from party',
          icon: Icons.person_remove,
          danger: true,
          onSelected: () => notifier.kick(p.userId),
        ),
      ],
      child: face,
    );
  }
}

/// Mic, camera and hide-self, as a vertical rail on the left edge of the
/// stage.
///
/// Separate from [_WatchChrome] because it belongs to a different box. That
/// chrome is a top strip one button tall; this needs the FULL stage height to
/// centre against, and cramming both into one row was what put five controls
/// into the same horizontal strip as the title and the window buttons.
///
/// Fades with the rest of the chrome, and stops taking input while hidden —
/// an invisible mute button is worse than no mute button.
class DeviceRail extends ConsumerWidget {
  const DeviceRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lkState = ref.watch(livekitProvider);
    final lk = ref.read(livekitProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AvPendingToggle(
            iconOn: Icons.mic,
            iconOff: Icons.mic_off,
            on: lkState.micEnabled,
            tooltip: lkState.micEnabled
                ? 'Mute microphone'
                : 'Unmute microphone',
            onToggle: () => lk.setMic(!lkState.micEnabled),
          ),
          _AvPendingToggle(
            iconOn: Icons.videocam,
            iconOff: Icons.videocam_off,
            on: lkState.cameraEnabled,
            tooltip: lkState.cameraEnabled
                ? 'Turn camera off'
                : 'Turn camera on',
            onToggle: () => lk.setCamera(!lkState.cameraEnabled),
          ),
          _AvIconButton(
            icon: lkState.hideSelf ? Icons.visibility_off : Icons.visibility,
            tooltip: lkState.hideSelf ? 'Show my tile' : 'Hide my tile',
            active: lkState.hideSelf,
            onTap: () => lk.setHideSelf(!lkState.hideSelf),
          ),
          // Reconnect is NOT here. It moved to the watch-party control panel:
          // the rail is the four things you reach for mid-film, and a repair
          // you need once a month does not earn a permanent seat among them.
        ],
      ),
    );
  }
}

/// A hairline separating groups of controls.
class _AvDivider extends StatelessWidget {
  const _AvDivider() : vertical = false;

  /// For a row of controls rather than a column — the control panel groups
  /// its glyphs the same way the rail does, turned ninety degrees.
  const _AvDivider.vertical() : vertical = true;

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: vertical ? 1 : 18,
      height: vertical ? 18 : 1,
      margin: vertical
          ? const EdgeInsets.symmetric(horizontal: 6)
          : const EdgeInsets.symmetric(vertical: 6),
      color: AppColors.line2,
    );
  }
}
