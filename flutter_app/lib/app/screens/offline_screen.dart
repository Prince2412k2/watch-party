import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../state/offline_provider.dart';
import '../../ui/ui.dart';

/// Offline library (PLAN §4 E8.3) — replaces the E0 placeholder at
/// `/offline`. Router wiring (already frozen, `lib/app/router.dart`):
///
/// ```dart
/// GoRoute(path: Routes.offline, builder: (_, _) => const OfflineScreen()),
/// ```
///
/// Redesign (PKG-A): a single path to detail — tapping a poster opens its
/// normal `/detail/:id` route (which resolves to the local file via
/// `openPreferringOffline`), carrying a `poster-<id>` Hero. The old duplicate
/// "Play" button is gone; the poster corner keeps just the delete action.
/// Posters stagger in via [Reveal].
class OfflineScreen extends ConsumerWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineProvider).toList()
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));

    // Unique Hero tag per screen. Records are already unique by itemId, but
    // claim-first-null-rest guards against a duplicate ever slipping in
    // (Flutter throws on duplicate Hero tags on one screen).
    final claimed = <String>{};
    final heroTags = [
      for (final r in offline)
        claimed.add(r.itemId) ? 'poster-${r.itemId}' : null,
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Offline', style: AppTheme.displaySmall),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Downloaded titles — play these with no network.',
                style: AppTheme.dim,
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: offline.isEmpty
                    ? const EmptyState(
                        icon: Icons.wifi_off_outlined,
                        title: 'No offline titles yet',
                        message:
                            'Download a title from its detail page to watch it here with no network.',
                      )
                    : GridView.builder(
                        // A fixed cell height (poster + caption) instead of an
                        // aspect ratio, so a cell can never clip its content at
                        // narrow column widths.
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180,
                              mainAxisSpacing: AppSpacing.xl,
                              crossAxisSpacing: AppSpacing.lg,
                              mainAxisExtent: 300,
                            ),
                        itemCount: offline.length,
                        itemBuilder: (context, i) => Reveal(
                          delay: AppMotion.stagger * (i < 10 ? i : 10),
                          child: _OfflineTile(
                            record: offline[i],
                            heroTag: heroTags[i],
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

class _OfflineTile extends ConsumerWidget {
  const _OfflineTile({required this.record, required this.heroTag});
  final OfflineRecord record;
  final String? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: Alignment.topLeft,
      child: Stack(
        children: [
          PosterCard(
            title: record.title,
            subtitle: _duration(record.runTimeTicks),
            heroTag: heroTag,
            onTap: () => context.go('/detail/${record.itemId}'),
          ),
          Positioned(
            top: AppSpacing.sm,
            right: AppSpacing.sm,
            child: IconButton(
              tooltip: 'Remove download',
              iconSize: 18,
              icon: const Icon(Icons.delete_outline),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: AppColors.text,
                minimumSize: const Size(32, 32),
                padding: const EdgeInsets.all(AppSpacing.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () async {
                final confirmed = await showConfirm(
                  context,
                  title: 'Remove download?',
                  body: '${record.title} will be deleted from this device.',
                  confirmLabel: 'Remove',
                  danger: true,
                );
                if (confirmed) {
                  await ref
                      .read(offlineProvider.notifier)
                      .remove(record.itemId);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  static String? _duration(int runTimeTicks) {
    if (runTimeTicks <= 0) return null;
    final minutes = (runTimeTicks / 10000000 / 60).round();
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}
