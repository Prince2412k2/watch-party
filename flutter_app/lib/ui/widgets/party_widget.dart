import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/state.dart';
import '../palette.dart';
import '../tokens.dart';
import 'app_button.dart';
import 'app_dialog.dart';
import 'join_code_dialog.dart';
import 'party_qr.dart';
import 'watch_party_animation.dart';

/// The expandable watch-party surface rendered inside the bottom-right
/// [PopcornControl] (`WebPartyWidget`, `WebShell.tsx`). It consumes the app-wide
/// [partyProvider] directly — never a duplicate — so its roster/waiting state
/// stays in lock-step with the `/party` route and survives navigation.
///
/// No session → "Start a watch party" (create) + "Join with a code" (an 8-char
/// hex [JoinCodeDialog]). Live → a QR invite + room code + copy-invite, the
/// people roster (host + kickable guests), the host approve/reject waiting list,
/// and a host "End party". Watching sessions navigate from the shell
/// automatically. Host-only actions are
/// gated by [PartyNotifier.isHost].
class PartyWidget extends ConsumerStatefulWidget {
  const PartyWidget({super.key});

  @override
  ConsumerState<PartyWidget> createState() => _PartyWidgetState();
}

class _PartyWidgetState extends ConsumerState<PartyWidget> {
  bool _starting = false;
  bool _copied = false;
  String? _error;

  PartyNotifier get _party => ref.read(partyProvider.notifier);

  Future<void> _start() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _party.create();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _join() async {
    setState(() => _error = null);
    await showDialog<String>(
      context: context,
      builder: (_) => JoinCodeDialog(onJoin: (code) => _party.join(code)),
    );
    if (!mounted) return;
    // The shell opens the player when the approved room enters watching.
  }

  void _copyInvite(String joinUrl) {
    Clipboard.setData(ClipboardData(text: joinUrl));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _end() async {
    final ok = await showConfirm(
      context,
      title: 'End this party?',
      body: 'The room closes for everyone.',
      confirmLabel: 'End party',
      danger: true,
    );
    if (ok) await _party.end();
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final session = ref.watch(partyProvider);
    final viewport = MediaQuery.sizeOf(context);
    final width = math.max(0.0, math.min(320.0, viewport.width - 38));
    final maxHeight = math.max(0.0, viewport.height - 82);

    return Container(
      key: const ValueKey('party-widget-panel'),
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: wp.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        border: Border.all(color: wp.line),
        boxShadow: wp.cardShadow,
      ),
      child: SingleChildScrollView(
        child: session == null ? _empty(wp) : _live(wp, session),
      ),
    );
  }

  Widget _empty(WpPalette wp) {
    if (_starting) {
      return SizedBox(
        height: 300,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const WatchPartyAnimation(size: 190),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Starting watch party',
              style: TextStyle(
                fontFamily: AppFonts.sans,
                color: wp.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _eyebrow('WATCH TOGETHER', wp),
        const SizedBox(height: 6),
        _title('Start a watch party', wp),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Invite friends, browse together, and keep every screen in sync.',
          style: TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 14,
            height: 1.5,
            color: wp.dim,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: _starting ? 'Starting…' : 'Start a party',
          icon: Icons.add,
          variant: AppButtonVariant.primary,
          busy: _starting,
          onPressed: _starting ? null : _start,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton(
          label: 'Join with a code',
          icon: Icons.login,
          variant: AppButtonVariant.secondary,
          onPressed: _join,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _errorText(_error!),
        ],
      ],
    );
  }

  Widget _live(WpPalette wp, PartyState session) {
    final isHost = _party.isHost;
    final waiting = ref.watch(partyWaitingProvider);
    final joinUrl =
        '${ref.watch(apiClientProvider).baseUrl}/party/${session.id}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _eyebrow('LIVE ROOM', wp),
        const SizedBox(height: 6),
        _title('Watch party', wp),
        const SizedBox(height: AppSpacing.lg),
        // Invite block: QR alongside the room code + copy-invite.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PartyQr(url: joinUrl, size: 96),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ROOM CODE',
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 10,
                      letterSpacing: 1,
                      color: wp.faint,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    session.id,
                    style: TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: wp.text,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: _copied ? 'Copied' : 'Copy invite',
                    icon: _copied ? Icons.check : Icons.copy,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => _copyInvite(joinUrl),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final p in session.participants)
          _Person(
            name: p.name,
            host: p.isHost,
            trailing: (isHost && !p.isHost)
                ? _IconAction(
                    icon: Icons.close,
                    tooltip: 'Remove',
                    onTap: () => _party.kick(p.userId),
                  )
                : null,
          ),
        if (isHost && waiting.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Waiting to join',
            style: TextStyle(
              fontFamily: AppFonts.sans,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: wp.dim,
            ),
          ),
          for (final p in waiting)
            _Person(
              name: p.name,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconAction(
                    icon: Icons.close,
                    tooltip: 'Reject',
                    onTap: () => _party.reject(p.userId),
                  ),
                  _IconAction(
                    icon: Icons.check,
                    tooltip: 'Approve',
                    onTap: () => _party.approve(p.userId),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: AppSpacing.xl),
        AppButton(
          label: isHost ? 'End party' : 'Leave party',
          variant: AppButtonVariant.danger,
          onPressed: () => isHost ? _end() : _party.leave(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _errorText(_error!),
        ],
      ],
    );
  }

  Widget _eyebrow(String text, WpPalette wp) => Text(
    text,
    style: TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 10,
      letterSpacing: 1.5,
      color: wp.faint,
    ),
  );

  Widget _title(String text, WpPalette wp) => Text(
    text,
    style: TextStyle(
      fontFamily: AppFonts.sans,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: wp.text,
    ),
  );

  Widget _errorText(String text) => Text(
    text,
    style: const TextStyle(
      fontFamily: AppFonts.sans,
      fontSize: 12.5,
      color: kSemanticRed,
    ),
  );
}

class _Person extends StatelessWidget {
  const _Person({required this.name, this.host = false, this.trailing});

  final String name;
  final bool host;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: wp.surface2,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(name),
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: wp.text,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 14,
                color: wp.text,
              ),
            ),
          ),
          if (host)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Text(
                'Host',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: wp.faint,
                ),
              ),
            ),
          ?trailing,
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        iconSize: 15,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        icon: Icon(icon, color: wp.dim),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = parts.map((w) => w[0]).join().toUpperCase();
  if (letters.isEmpty) return '?';
  return letters.length > 2 ? letters.substring(0, 2) : letters;
}
