import 'package:flutter/material.dart';

import '../../ui/ui.dart';

/// Simple placeholder screens (PLAN §3.7). Each owning epic replaces its screen;
/// Phase 0 gives every route a real, navigable widget.
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

class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _Placeholder(title: 'Browse', body: 'Search + grid + filters (E3).');
}

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.itemId});
  final String itemId;
  @override
  Widget build(BuildContext context) =>
      _Placeholder(title: 'Title detail', body: 'Item $itemId — metadata, Play, Download (E3/E4).');
}

class PartyScreen extends StatelessWidget {
  const PartyScreen({super.key, this.partyId});
  final String? partyId;
  @override
  Widget build(BuildContext context) => _Placeholder(
      title: 'Watch Party',
      body: partyId == null ? 'Create or join a party (E5/E6/E7).' : 'Party $partyId');
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _Placeholder(title: 'Downloads', body: 'Resumable downloads + progress (E8).');
}

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _Placeholder(title: 'Offline', body: 'Downloaded titles, play with no network (E8).');
}

class ServarrScreen extends StatelessWidget {
  const ServarrScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _Placeholder(title: 'Find & Download', body: 'Servarr search / releases / queue (E9).');
}
