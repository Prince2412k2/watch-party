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
class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.destinations,
    required this.currentRoute,
    required this.onSelect,
    this.width = 240,
  });

  final List<NavDestination> destinations;
  final String currentRoute;
  final ValueChanged<String> onSelect;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: AppSpacing.sm, bottom: AppSpacing.xl),
            child: Text('Watchparty',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text)),
          ),
          for (final d in destinations)
            _NavRow(
              dest: d,
              active: currentRoute == d.route,
              onTap: () => onSelect(d.route),
            ),
        ],
      ),
    );
  }
}

class _NavRow extends StatefulWidget {
  const _NavRow({required this.dest, required this.active, required this.onTap});
  final NavDestination dest;
  final bool active;
  final VoidCallback onTap;
  @override
  State<_NavRow> createState() => _NavRowState();
}

class _NavRowState extends State<_NavRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final color = active || _hover ? AppColors.text : AppColors.dim;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          decoration: BoxDecoration(
            color: _hover && !active ? const Color(0x0AFFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          child: Row(
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
  }
}
