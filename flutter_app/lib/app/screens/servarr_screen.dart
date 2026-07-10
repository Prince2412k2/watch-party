import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';

/// E9 T9.1 — Find/Download screen. Search Radarr (movies) / Sonarr (series),
/// browse a discover rail when there's no query, and one-tap "request" a
/// title — the server runs add → live release search → grab-or-remove and
/// hands back a definitive outcome, so the card just reflects it. Mirrors
/// `app/client/src/pages/FindDownload.jsx`.
class ServarrScreen extends ConsumerStatefulWidget {
  const ServarrScreen({super.key});

  @override
  ConsumerState<ServarrScreen> createState() => _ServarrScreenState();
}

class _ServarrScreenState extends ConsumerState<ServarrScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(servarrHealthProvider);
    final search = ref.watch(servarrSearchProvider);
    final notifier = ref.read(servarrSearchProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Find & Download'),
          const SizedBox(height: AppSpacing.md),
          _SearchBar(
            controller: _controller,
            kind: search.kind,
            loading: search.loading,
            onKindChanged: notifier.setKind,
            onChanged: notifier.setTerm,
            onSubmitted: (_) => notifier.submit(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: health.when(
              loading: () => const _GridSkeleton(),
              error: (e, _) => ErrorState(
                title: 'Could not check service status',
                message: e.toString(),
              ),
              data: (h) {
                final ready = servarrServiceReady(h, search.kind.service);
                if (!ready) {
                  return EmptyState(
                    title: '${search.kind.service[0].toUpperCase()}${search.kind.service.substring(1)} is unavailable',
                    message: 'This service isn\'t configured or isn\'t reachable right now.',
                    icon: Icons.cloud_off_outlined,
                  );
                }
                if (search.error != null) {
                  return ErrorState(
                    title: search.error!,
                    onRetry: notifier.submit,
                  );
                }
                if (search.loading) return const _GridSkeleton();
                if (!search.hasSearched) {
                  return _PopularRail(kind: search.kind, notifier: notifier);
                }
                if (search.results.isEmpty) {
                  return EmptyState(
                    title: 'No matches',
                    message: 'Nothing found for "${search.term.trim()}". Try a different title.',
                    icon: Icons.search_off,
                  );
                }
                return _ResultGrid(
                  results: search.results,
                  kind: search.kind,
                  stateFor: notifier.stateFor,
                  onRequest: notifier.request,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.kind,
    required this.loading,
    required this.onKindChanged,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ServarrKind kind;
  final bool loading;
  final ValueChanged<ServarrKind> onKindChanged;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AppChip(
          label: 'Movies',
          icon: Icons.movie_outlined,
          selected: kind == ServarrKind.movie,
          onTap: () => onKindChanged(ServarrKind.movie),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppChip(
          label: 'Series',
          icon: Icons.tv_outlined,
          selected: kind == ServarrKind.series,
          onTap: () => onKindChanged(ServarrKind.series),
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: AppTextField(
            controller: controller,
            hint: 'Search ${kind == ServarrKind.movie ? 'movies' : 'series'} by title…',
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        if (loading) ...[
          const SizedBox(width: AppSpacing.md),
          const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: 12,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.lg,
        childAspectRatio: 0.5,
      ),
      itemBuilder: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: LoadingSkeleton(borderRadius: AppSpacing.radius, height: double.infinity)),
          const SizedBox(height: AppSpacing.sm),
          const LoadingSkeleton(height: 12, width: 100),
        ],
      ),
    );
  }
}

class _PopularRail extends ConsumerWidget {
  const _PopularRail({required this.kind, required this.notifier});
  final ServarrKind kind;
  final ServarrSearchNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final popular = ref.watch(servarrPopularProvider(kind));
    return popular.when(
      loading: () => const _GridSkeleton(),
      error: (_, _) => EmptyState(
        title: 'Find something to watch',
        message: 'Search ${kind == ServarrKind.movie ? 'movies' : 'series'} by title above.',
        icon: Icons.search,
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            title: 'Find something to watch',
            message: 'Search ${kind == ServarrKind.movie ? 'movies' : 'series'} by title above.',
            icon: Icons.search,
          );
        }
        return _ResultGrid(
          results: items,
          kind: kind,
          stateFor: notifier.stateFor,
          onRequest: notifier.request,
        );
      },
    );
  }
}

class _ResultGrid extends StatelessWidget {
  const _ResultGrid({
    required this.results,
    required this.kind,
    required this.stateFor,
    required this.onRequest,
  });

  final List<ServarrTitle> results;
  final ServarrKind kind;
  final ServarrRequestState Function(ServarrTitle) stateFor;
  final ValueChanged<ServarrTitle> onRequest;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: results.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: AppSpacing.lg,
        crossAxisSpacing: AppSpacing.lg,
        childAspectRatio: 0.5,
      ),
      itemBuilder: (context, i) {
        final t = results[i];
        return _ResultCard(
          title: t,
          kind: kind,
          state: stateFor(t),
          onTap: () => _showDetail(context, t, kind, stateFor(t), onRequest),
          onRequest: () => onRequest(t),
        );
      },
    );
  }
}

void _showDetail(
  BuildContext context,
  ServarrTitle t,
  ServarrKind kind,
  ServarrRequestState state,
  ValueChanged<ServarrTitle> onRequest,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusLg)),
    ),
    builder: (_) => _DetailSheet(title: t, kind: kind, state: state, onRequest: onRequest),
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.title,
    required this.kind,
    required this.state,
    required this.onTap,
    required this.onRequest,
  });

  final ServarrTitle title;
  final ServarrKind kind;
  final ServarrRequestState state;
  final VoidCallback onTap;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            child: Material(
              color: AppColors.surface2,
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (title.posterUrl != null)
                      Image.network(title.posterUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const _PosterFallback())
                    else
                      const _PosterFallback(),
                    if (title.rating != null)
                      Positioned(
                        top: 6, left: 6,
                        child: _RatingBadge(rating: title.rating!),
                      ),
                    Positioned(
                      left: 6, right: 6, bottom: 6,
                      child: _StatusBar(state: state, onRequest: onRequest),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(title.title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.body),
        Text(
          [title.year?.toString(), title.network].where((e) => e != null && e.isNotEmpty).join(' · '),
          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.mono,
        ),
      ],
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();
  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: AppColors.surface2, child: Center(child: Icon(Icons.movie_outlined, color: AppColors.faint)));
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});
  final double rating;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 11, color: AppColors.text),
          const SizedBox(width: 3),
          Text(rating.toStringAsFixed(1), style: AppTheme.mono.copyWith(fontSize: 11)),
        ],
      ),
    );
  }
}

/// Bottom overlay reflecting the request state, same as the web hover card.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state, required this.onRequest});
  final ServarrRequestState state;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case ServarrRequestState.searching:
        return const _Pill(icon: Icons.hourglass_top, label: 'Finding a release…');
      case ServarrRequestState.grabbed:
        return const _Pill(icon: Icons.download, label: 'Downloading', live: true);
      case ServarrRequestState.monitoring:
        return const _Pill(icon: Icons.auto_awesome, label: 'Monitoring');
      case ServarrRequestState.added:
        return const _Pill(icon: Icons.check, label: 'In library');
      case ServarrRequestState.noRelease:
        return _RetryPill(label: 'No release — retry', onTap: onRequest);
      case ServarrRequestState.searchFailed:
        return _RetryPill(label: 'Retry', onTap: onRequest);
      case ServarrRequestState.error:
        return _RetryPill(label: 'Retry', onTap: onRequest, danger: true);
      case ServarrRequestState.idle:
        return _DownloadButton(onTap: onRequest);
    }
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, this.live = false});
  final IconData icon;
  final String label;
  final bool live;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: live ? AppColors.live : AppColors.text),
          const SizedBox(width: 5),
          Flexible(
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(color: AppColors.text)),
          ),
        ],
      ),
    );
  }
}

class _RetryPill extends StatelessWidget {
  const _RetryPill({required this.label, required this.onTap, this.danger = false});
  final String label;
  final VoidCallback onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: danger ? const Color(0x1AE0655E) : AppColors.accent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh, size: 13, color: danger ? AppColors.red : AppColors.onAccent),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(color: danger ? AppColors.red : AppColors.onAccent)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.download, size: 13, color: AppColors.onAccent),
              SizedBox(width: 5),
              Text('Download', style: TextStyle(color: AppColors.onAccent, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  const _DetailSheet({
    required this.title,
    required this.kind,
    required this.state,
    required this.onRequest,
  });

  final ServarrTitle title;
  final ServarrKind kind;
  final ServarrRequestState state;
  final ValueChanged<ServarrTitle> onRequest;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  child: SizedBox(
                    width: 90, height: 135,
                    child: title.posterUrl != null
                        ? Image.network(title.posterUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const _PosterFallback())
                        : const _PosterFallback(),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.title, style: AppTheme.titleLarge),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        [
                          title.year?.toString(),
                          kind == ServarrKind.series && title.seasonCount != null
                              ? '${title.seasonCount} seasons'
                              : null,
                          title.network,
                          title.status,
                        ].where((e) => e != null && e.isNotEmpty).join(' · '),
                        style: AppTheme.dim,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (title.overview != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(title.overview!, style: AppTheme.body, maxLines: 6, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: AppSpacing.xl),
            _DetailAction(state: state, onRequest: () {
              onRequest(title);
              Navigator.of(context).pop();
            }),
          ],
        ),
      ),
    );
  }
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({required this.state, required this.onRequest});
  final ServarrRequestState state;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case ServarrRequestState.added:
        return const AppButton(label: 'In library', icon: Icons.check, expand: true);
      case ServarrRequestState.monitoring:
        return const AppButton(label: 'Added — monitoring', icon: Icons.auto_awesome, expand: true);
      case ServarrRequestState.searching:
        return const AppButton(label: 'Finding a release…', busy: true, expand: true);
      case ServarrRequestState.noRelease:
        return AppButton(label: 'Try again', icon: Icons.refresh, expand: true, onPressed: onRequest);
      case ServarrRequestState.searchFailed:
      case ServarrRequestState.error:
        return AppButton(label: 'Retry', icon: Icons.refresh, expand: true, onPressed: onRequest, variant: AppButtonVariant.danger);
      case ServarrRequestState.idle:
      case ServarrRequestState.grabbed:
        return AppButton(
          label: state == ServarrRequestState.grabbed ? 'Downloading' : 'Download',
          icon: Icons.download,
          expand: true,
          variant: AppButtonVariant.primary,
          onPressed: state == ServarrRequestState.grabbed ? null : onRequest,
        );
    }
  }
}
