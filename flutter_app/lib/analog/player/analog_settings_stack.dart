// The settings gear.
//
// "Activating the gear expands a compact vertical stack upward from the
// lower-right control area. It does not open a full-screen modal."
// (docs/watchparty-design/player-interface-reference.md)
//
// The direct subtitle action deliberately stays OUTSIDE this stack — fast track
// selection and Off must not cost two taps.


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
            child: _SettingsPanel(
              animate: animate,
              children: [
                for (var i = 0; i < widget.entries.length; i++)
                  _SettingsRow(
                    entry: widget.entries[i],
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

/// The one plate the rows sit in.
///
/// They used to be separate floating pills, one per setting, each with its own
/// fill and corners and a gap between them. That reads as a column of
/// unrelated buttons; a settings menu is one object with rows in it.
class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.children, required this.animate});

  final List<Widget> children;
  final bool animate;

  /// Fixed, so every value lands on the same right edge instead of the panel
  /// resizing itself around whichever setting has the longest current value.
  static const double _width = 264;

  @override
  Widget build(BuildContext context) {
    final panel = SizedBox(
      width: _width,
      child: Material(
        color: AnalogColor.stageSurface,
        borderRadius: BorderRadius.circular(AnalogRadius.cardPx),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
    if (!animate) return panel;
    // Short travel, no overshoot: the panel rises a few px into place.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AnalogMotion.detentMs,
      curve: AnalogMotion.detentEase,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * AnalogSpace.smPx),
          child: child,
        ),
      ),
      child: panel,
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.entry, required this.onTap});

  final AnalogSettingsEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = entry.enabled ? AnalogColor.ink : AnalogColor.inkFaint;
    return InkWell(
      onTap: onTap,
      hoverColor: AnalogColor.stageSurface2,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AnalogSpace.mdPx,
          vertical: AnalogSpace.smPx + 3,
        ),
        child: Row(
          children: [
            Icon(entry.icon, size: 18, color: ink),
            const SizedBox(width: AnalogSpace.smPx + 2),
            Expanded(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // The current value sits against the chevron, quieter than the
            // label — you scan the labels to find the setting, then read one
            // value.
            if (entry.detail != null)
              Padding(
                padding: const EdgeInsets.only(left: AnalogSpace.smPx),
                child: Text(
                  entry.detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AnalogColor.inkDim,
                    fontSize: 13.5,
                  ),
                ),
              ),
            const SizedBox(width: AnalogSpace.xsPx),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: entry.enabled
                  ? AnalogColor.inkFaint
                  : AnalogColor.inkFaint,
            ),
          ],
        ),
      ),
    );
  }
}
