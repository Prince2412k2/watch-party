import 'package:flutter/material.dart';

import '../palette.dart';
import '../tokens.dart';

/// A rail/section title with an optional trailing action ("See all", a
/// count, a filter button). Used by Home rails, Browse sections, Downloads
/// groups — anywhere content is broken into labeled rows.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500, color: wp.text, letterSpacing: -0.2)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12.5, color: wp.faint)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
