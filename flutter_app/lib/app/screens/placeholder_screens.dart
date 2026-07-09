import 'package:flutter/material.dart';

import '../../ui/ui.dart';

/// Remaining placeholder screen(s). Browse/Detail (E3), Downloads/Offline (E8),
/// and Servarr (E9) now have real implementations in their own files; PartyScreen
/// is still a placeholder until E5 (Wave 3) replaces it.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, this.body});
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          if (body != null) Text(body!, style: AppTheme.dim),
        ],
      ),
    );
  }
}

class PartyScreen extends StatelessWidget {
  const PartyScreen({super.key, this.partyId});
  final String? partyId;
  @override
  Widget build(BuildContext context) => _Placeholder(
      title: 'Watch Party',
      body: partyId == null ? 'Create or join a party (E5/E6/E7).' : 'Party $partyId');
}
