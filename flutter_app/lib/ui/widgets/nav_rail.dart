import 'package:flutter/material.dart';

import '../tokens.dart';

/// A single navigation destination for [NavRail].
class NavDestination {
  const NavDestination({required this.icon, required this.label, required this.route, this.badge = 0});
  final IconData icon;
  final String label;
  final String route;
  final int badge;
}

/// FROZEN CONTRACT (PLAN §3.6). The app shell's left navigation. Active row is
/// brighter + heavier text only (no fill/rail/dot — per the shipped system). E1
/// finalizes the shell; E3/E8 supply destinations + badges.
///
/// [compact] collapses to an icon-only rail (labels become tooltips) for
/// narrow windows — additive, default `false` keeps the original contract.
class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.destinations,
    required this.currentRoute,
    required this.onSelect,
    this.width = 240,
    this.compact = false,
  });

  final List<NavDestination> destinations;
  final String currentRoute;
  final ValueChanged<String> onSelect;
  final double width;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 72 : width,
      color: AppColors.bg,
      padding: EdgeInsets.symmetric(horizontal: compact ? AppSpacing.sm : AppSpacing.lg, vertical: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.only(left: compact ? 0 : AppSpacing.sm, bottom: AppSpacing.xl),
            child: compact
                ? const Icon(Icons.theaters_outlined, color: AppColors.text, size: 20)
                : const Text('Watchparty',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
          for (final d in destinations)
            _NavRow(
              dest: d,
              active: currentRoute == d.route,
              compact: compact,
              onTap: () => onSelect(d.route),
            ),
        ],
      ),
    );
  }
}

class _NavRow extends StatefulWidget {
  const _NavRow({required this.dest, required this.active, required this.onTap, this.compact = false});
  final NavDestination dest;
  final bool active;
  final VoidCallback onTap;
  final bool compact;
  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final color = active || _hover ? AppColors.text : AppColors.dim;

    final row = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : AppSpacing.md, vertical: 10),
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          decoration: BoxDecoration(
            color: _hover && !active ? const Color(0x0AFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          child: widget.compact
              ? SizedBox(
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(widget.dest.icon, size: 20, color: color),
                      if (widget.dest.badge > 0)
                        Positioned(
                          top: 4, right: 12,
                          child: Container(
                            width: 6, height: 6,
                            decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    Icon(widget.dest.icon, size: 19, color: color),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(widget.dest.label,
                          style: TextStyle(
                              color: color,
                              fontSize: 14.5,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                    ),
                    if (widget.dest.badge > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0x2E5AB98A),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: Text('${widget.dest.badge}',
                            style: const TextStyle(color: AppColors.green, fontSize: 11.5, fontWeight: FontWeight.w700, fontFamily: AppFonts.mono)),
                      ),
                  ],
                ),
        ),
      ),
    );

    return widget.compact ? Tooltip(message: widget.dest.label, child: row) : row;
  }
}
