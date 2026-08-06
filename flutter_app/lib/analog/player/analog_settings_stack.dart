// The settings gear.
//
// "Activating the gear expands a compact vertical stack upward from the
// lower-right control area. It does not open a full-screen modal."
// (docs/watchparty-design/player-interface-reference.md)
//
// The direct subtitle action deliberately stays OUTSIDE this stack — fast track
// selection and Off must not cost two taps.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';

@immutable
class AnalogSettingsEntry {
  const AnalogSettingsEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
    this.enabled = true,
  });

  final IconData icon;
  final String label;

  /// The current value, shown trailing (e.g. "Hardware").
  final String? detail;
  final VoidCallback onTap;

  /// A row the viewer may see but not act on — a guest looking at a
  /// host-owned setting. Shown greyed rather than dropped, so the capability
  /// stays visible and its state readable.
  final bool enabled;
}

class AnalogSettingsStack extends StatefulWidget {
  const AnalogSettingsStack({
    super.key,
    required this.entries,
    this.enabled = true,
    this.onOpenChanged,
    this.tooltip = 'Settings',
  });

  final List<AnalogSettingsEntry> entries;
  final bool enabled;

  /// Raised while the stack is expanded so the caller can pin the chrome open —
  /// without it the menu vanishes under the cursor after three seconds.
  final ValueChanged<bool>? onOpenChanged;

  final String tooltip;

  @override
  State<AnalogSettingsStack> createState() => _AnalogSettingsStackState();
}

class _AnalogSettingsStackState extends State<AnalogSettingsStack> {
  final _link = LayerLink();
  OverlayEntry? _entry;

  bool get _open => _entry != null;

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _close() {
    if (_entry == null) return;
    _entry!.remove();
    _entry = null;
    widget.onOpenChanged?.call(false);
    if (mounted) setState(() {});
  }

  void _toggle() {
    if (_open) {
      _close();
      return;
    }
    if (widget.entries.isEmpty) return;
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    widget.onOpenChanged?.call(true);
    setState(() {});
  }

  Widget _buildOverlay(BuildContext context) {
    final animate = !MediaQuery.of(context).disableAnimations;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          // The stack's BOTTOM edge is pinned to the gear's TOP edge, so it
          // grows upward out of the lower-right control area.
          targetAnchor: Alignment.topRight,
          followerAnchor: Alignment.bottomRight,
          offset: const Offset(0, -AnalogSpace.xsPx),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < widget.entries.length; i++)
                  _SettingsRow(
                    entry: widget.entries[i],
                    // Rows settle from the bottom up, one short detent apart.
                    delay: animate
                        ? AnalogMotion.detentMs *
                              (widget.entries.length - 1 - i)
                        : Duration.zero,
                    animate: animate,
                    onTap: !widget.entries[i].enabled
                        ? null
                        : () {
                            _close();
                            widget.entries[i].onTap();
                          },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: Tooltip(
        message: widget.tooltip,
        child: IconButton(
          onPressed: widget.enabled ? _toggle : null,
          icon: const Icon(Icons.settings, size: 20),
          color: widget.enabled
              ? (_open ? AnalogColor.ink : AnalogColor.inkDim)
              : AnalogColor.inkFaint,
          splashRadius: 20,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.entry,
    required this.delay,
    required this.animate,
    required this.onTap,
  });

  final AnalogSettingsEntry entry;
  final Duration delay;
  final bool animate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: AnalogSpace.xsPx),
      child: Material(
        color: AnalogColor.stageSurface2,
        borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
          hoverColor: AnalogColor.stageSurface3,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AnalogSpace.mdPx,
              vertical: AnalogSpace.smPx,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  entry.icon,
                  size: 16,
                  color: entry.enabled
                      ? AnalogColor.inkDim
                      : AnalogColor.inkFaint,
                ),
                const SizedBox(width: AnalogSpace.smPx),
                Text(
                  entry.label,
                  style: TextStyle(
                    color: entry.enabled
                        ? AnalogColor.ink
                        : AnalogColor.inkFaint,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.detail != null) ...[
                  const SizedBox(width: AnalogSpace.mdPx),
                  Text(
                    entry.detail!,
                    style: const TextStyle(
                      color: AnalogColor.inkFaint,
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (!animate) return row;
    // Short travel, no overshoot: the row rises a few px into place.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AnalogMotion.detentMs + delay,
      curve: Interval(
        delay.inMicroseconds /
            math.max(1, (AnalogMotion.detentMs + delay).inMicroseconds),
        1,
        curve: AnalogMotion.detentEase,
      ),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * AnalogSpace.smPx),
          child: child,
        ),
      ),
      child: row,
    );
  }
}
