import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
import '../../state/offline_provider.dart';
import '../../ui/ui.dart';
import 'detail_screen.dart' show DetailScreen;

/// Offline library (PLAN §4 E8.3) — replaces the E0 placeholder at
/// `/offline`. Router wiring (already frozen, `lib/app/router.dart`):
///
/// ```dart
/// GoRoute(path: Routes.offline, builder: (_, _) => const OfflineScreen()),
/// ```
/// with `import '../screens/offline_screen.dart';` swapped in for the
/// placeholder's `OfflineScreen` import — class name unchanged.
///
/// "Play" here opens the title's normal `/detail/:id` route, which resolves
/// to the local file automatically once E4.2's player uses
/// `openPreferringOffline` (`lib/player/offline_playback.dart`) — no
/// network round-trip needed since [OfflineRecord.filePath] is already local.
class OfflineScreen extends ConsumerWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineProvider).toList()
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));

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
              const Text('Downloaded titles — play these with no network.', style: AppTheme.dim),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: offline.isEmpty
                    ? const EmptyState(
                        icon: Icons.wifi_off_outlined,
                        title: 'No offline titles yet',
                        message: 'Download a title from its detail page to watch it here with no network.',
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          mainAxisSpacing: AppSpacing.xl,
                          crossAxisSpacing: AppSpacing.lg,
                          childAspectRatio: 0.56,
                        ),
                        itemCount: offline.length,
                        itemBuilder: (context, i) => _OfflineTile(record: offline[i]),
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
  const _OfflineTile({required this.record});
  final OfflineRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        PosterCard(
          title: record.title,
          subtitle: _duration(record.runTimeTicks),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => DetailScreen(itemId: record.itemId)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            AppButton(
              label: 'Play',
              variant: AppButtonVariant.primary,
              icon: Icons.play_arrow,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DetailScreen(itemId: record.itemId)),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Remove download',
              icon: const Icon(Icons.delete_outline, color: AppColors.faint),
              onPressed: () async {
                final confirmed = await showConfirm(
                  context,
                  title: 'Remove download?',
                  body: '${record.title} will be deleted from this device.',
                  confirmLabel: 'Remove',
                  danger: true,
                );
                if (confirmed) {
                  await ref.read(offlineProvider.notifier).remove(record.itemId);
                }
              },
            ),
          ],
        ),
      ],
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
