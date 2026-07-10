import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

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
                    title:
                        '${search.kind.service[0].toUpperCase()}${search.kind.service.substring(1)} is unavailable',
                    message:
                        'This service isn\'t configured or isn\'t reachable right now.',
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
                    message:
                        'Nothing found for "${search.term.trim()}". Try a different title.',
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
        // Movies / Series as a shadcn toggle-group: outline segments, the
        // active kind rendered filled (Toggle's selected state).
        sc.ButtonGroup(
          children: [
            for (final k in ServarrKind.values)
              sc.Toggle(
                value: kind == k,
                style: const sc.ButtonStyle.outline(),
                onChanged: (on) {
                  if (on) onKindChanged(k);
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      k == ServarrKind.movie
                          ? Icons.movie_outlined
                          : Icons.tv_outlined,
                      size: 16,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(k.label),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: AppTextField(
            controller: controller,
            hint:
                'Search ${kind == ServarrKind.movie ? 'movies' : 'series'} by title…',
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
        if (loading) ...[
          const SizedBox(width: AppSpacing.md),
          const SizedBox(
            width: 18,
            height: 18,
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
          Expanded(
            child: LoadingSkeleton(
              borderRadius: AppSpacing.radius,
              height: double.infinity,
            ),
          ),
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
        message:
            'Search ${kind == ServarrKind.movie ? 'movies' : 'series'} by title above.',
        icon: Icons.search,
      ),
      data: (items) {
        if (items.isEmpty) {
          return EmptyState(
            title: 'Find something to watch',
            message:
                'Search ${kind == ServarrKind.movie ? 'movies' : 'series'} by title above.',
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
        // Index-delayed reveal for a staggered grid entrance; capped so a full
        // page of results doesn't animate for seconds.
        return Reveal(
          delay: AppMotion.stagger * math.min(i, 8),
          child: _ResultCard(
            title: t,
            kind: kind,
            state: stateFor(t),
            onTap: () => _showDetail(context, t, kind, stateFor(t), onRequest),
            onRequest: () => onRequest(t),
          ),
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
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusLg),
      ),
    ),
    builder: (_) =>
        _DetailSheet(title: t, kind: kind, state: state, onRequest: onRequest),
  );
}

/// A search/discover result. Mirrors [PosterCard]'s frame (sc.Card, hover
/// scale, rounded poster) but keeps the two overlays this screen needs — a
/// rating badge and a live request/status control — which [PosterCard] has no
/// slots for, so it can't be reused verbatim here.
class _ResultCard extends StatefulWidget {
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
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedScale(
                scale: _hover ? 1.03 : 1.0,
                duration: AppMotion.hover,
                curve: AppMotion.standard,
                child: sc.Card(
                  padding: EdgeInsets.zero,
                  filled: true,
                  fillColor: AppColors.surface2,
                  borderColor: _hover ? AppColors.line2 : Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (t.posterUrl != null)
                          Image.network(
                            t.posterUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const _PosterFallback(),
                          )
                        else
                          const _PosterFallback(),
                        if (t.rating != null)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: _RatingBadge(rating: t.rating!),
                          ),
                        // Bottom-left, shrink-wrapped so it never forces width
                        // (labels are short); the ClipRRect guards the corners.
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _StatusControl(
                            state: widget.state,
                            onRequest: widget.onRequest,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          t.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          [
            t.year?.toString(),
            t.network,
          ].where((e) => e != null && e.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.mono,
        ),
      ],
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.surface2,
    child: Center(child: Icon(Icons.movie_outlined, color: AppColors.faint)),
  );
}

/// Rating chip on a poster — an `sc` badge replacing the hand-rolled pill.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});
  final double rating;
  @override
  Widget build(BuildContext context) {
    return sc.SecondaryBadge(
      leading: const Icon(Icons.star, size: 11, color: AppColors.text),
      child: Text(
        rating.toStringAsFixed(1),
        style: AppTheme.mono.copyWith(fontSize: 11),
      ),
    );
  }
}

/// The poster's bottom overlay, reflecting the request state. Non-interactive
/// states render an `sc` badge; actionable states render an `sc` button (the
/// old `_Pill`/`_RetryPill`/`_DownloadButton` trio, unified).
class _StatusControl extends StatelessWidget {
  const _StatusControl({required this.state, required this.onRequest});
  final ServarrRequestState state;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case ServarrRequestState.searching:
        return const _StatusBadge(
          icon: Icons.hourglass_top,
          label: 'Searching…',
        );
      case ServarrRequestState.grabbed:
        return const _StatusBadge(
          icon: Icons.download,
          label: 'Downloading',
          live: true,
        );
      case ServarrRequestState.monitoring:
        return const _StatusBadge(
          icon: Icons.auto_awesome,
          label: 'Monitoring',
        );
      case ServarrRequestState.added:
        return const _StatusBadge(icon: Icons.check, label: 'In library');
      case ServarrRequestState.noRelease:
        return _StatusButton(
          icon: Icons.refresh,
          label: 'No release',
          onTap: onRequest,
          style: const sc.ButtonStyle.secondary(
            size: sc.ButtonSize.small,
            density: sc.ButtonDensity.dense,
          ),
        );
      case ServarrRequestState.searchFailed:
        return _StatusButton(
          icon: Icons.refresh,
          label: 'Retry',
          onTap: onRequest,
          style: const sc.ButtonStyle.secondary(
            size: sc.ButtonSize.small,
            density: sc.ButtonDensity.dense,
          ),
        );
      case ServarrRequestState.error:
        return _StatusButton(
          icon: Icons.refresh,
          label: 'Retry',
          onTap: onRequest,
          style: const sc.ButtonStyle.destructive(
            size: sc.ButtonSize.small,
            density: sc.ButtonDensity.dense,
          ),
        );
      case ServarrRequestState.idle:
        return _StatusButton(
          icon: Icons.download,
          label: 'Download',
          onTap: onRequest,
          style: const sc.ButtonStyle.primary(
            size: sc.ButtonSize.small,
            density: sc.ButtonDensity.dense,
          ),
        );
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.icon,
    required this.label,
    this.live = false,
  });
  final IconData icon;
  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return sc.SecondaryBadge(
      leading: Icon(
        icon,
        size: 12,
        color: live ? AppColors.live : AppColors.text,
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.style,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final sc.AbstractButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return sc.Button(
      style: style,
      onPressed: onTap,
      leading: Icon(icon, size: 13),
      child: Text(label),
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
    final genres = title.genres.where((g) => g.isNotEmpty).take(5).toList();
    final meta = [
      title.year?.toString(),
      kind == ServarrKind.series && title.seasonCount != null
          ? '${title.seasonCount} seasons'
          : null,
      title.network,
      title.status,
    ].where((e) => e != null && e.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: StaggeredList(
          spacing: AppSpacing.lg,
          children: [
            // Grab handle.
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line2,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                      child: SizedBox(
                        width: 90,
                        height: 135,
                        child: title.posterUrl != null
                            ? Image.network(
                                title.posterUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const _PosterFallback(),
                              )
                            : const _PosterFallback(),
                      ),
                    ),
                    if (title.rating != null)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: _RatingBadge(rating: title.rating!),
                      ),
                  ],
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.title, style: AppTheme.titleLarge),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(meta, style: AppTheme.dim),
                      ],
                      if (genres.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [for (final g in genres) AppChip(label: g)],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (title.overview != null)
              Text(
                title.overview!,
                style: AppTheme.body,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            _DetailAction(
              state: state,
              onRequest: () {
                onRequest(title);
                Navigator.of(context).pop();
              },
            ),
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
        return const AppButton(
          label: 'In library',
          icon: Icons.check,
          expand: true,
        );
      case ServarrRequestState.monitoring:
        return const AppButton(
          label: 'Added — monitoring',
          icon: Icons.auto_awesome,
          expand: true,
        );
      case ServarrRequestState.searching:
        return const AppButton(
          label: 'Finding a release…',
          busy: true,
          expand: true,
        );
      case ServarrRequestState.noRelease:
        return AppButton(
          label: 'Try again',
          icon: Icons.refresh,
          expand: true,
          onPressed: onRequest,
        );
      case ServarrRequestState.searchFailed:
      case ServarrRequestState.error:
        return AppButton(
          label: 'Retry',
          icon: Icons.refresh,
          expand: true,
          onPressed: onRequest,
          variant: AppButtonVariant.danger,
        );
      case ServarrRequestState.idle:
      case ServarrRequestState.grabbed:
        return AppButton(
          label: state == ServarrRequestState.grabbed
              ? 'Downloading'
              : 'Download',
          icon: Icons.download,
          expand: true,
          variant: AppButtonVariant.primary,
          onPressed: state == ServarrRequestState.grabbed ? null : onRequest,
        );
    }
  }
}
