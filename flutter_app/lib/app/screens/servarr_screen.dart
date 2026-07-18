import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';
import 'servarr_detail_screen.dart';

/// Discover — the redesign collapses browse + acquire into one search-free
/// surface (design guide §Library and discovery shelves; no search field). Two
/// fixed horizontal rails — Movies (radarr) and Shows (sonarr) — built on
/// [PosterShelf]/[PosterCard], each fed by `GET /api/servarr/{service}/discover`
/// and degrading to a per-rail "unavailable" state independently. Tapping a
/// poster opens the full acquire detail in place. Mirrors
/// `app/client/src/pages/FindDownload.tsx` (the `Browse` export).
class ServarrScreen extends ConsumerStatefulWidget {
  const ServarrScreen({super.key});

  @override
  ConsumerState<ServarrScreen> createState() => _ServarrScreenState();
}

class _ServarrScreenState extends ConsumerState<ServarrScreen> {
  ServarrTitle? _selected;
  ServarrKind _selectedKind = ServarrKind.movie;
  ServarrKind _activeKind = ServarrKind.movie;
  String _query = '';
  Timer? _searchTimer;

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  void _setQuery(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _open(ServarrTitle item, ServarrKind kind) {
    setState(() {
      _selected = item;
      _selectedKind = kind;
    });
  }

  @override
  Widget build(BuildContext context) {
    final health = ref.watch(servarrHealthProvider);

    return health.when(
      loading: () => const _RailsSkeleton(),
      error: (e, _) => ErrorState(
        title: 'Could not check service status',
        message: e.toString(),
      ),
      data: (h) {
        final qbitReady = servarrServiceReady(h, 'qbittorrent');
        // One shared poller for the page; gated on qBittorrent readiness so the
        // Discover cards + detail can overlay live-download progress.
        final torrents = qbitReady
            ? ref.watch(servarrDownloadsPollProvider).valueOrNull?.list
            : null;

        if (_selected != null) {
          return ServarrDetailView(
            item: _selected!,
            kind: _selectedKind,
            torrents: torrents,
            onBack: () => setState(() => _selected = null),
          );
        }

        final compact = MediaQuery.sizeOf(context).width < 600;
        return ListView(
          padding: EdgeInsets.fromLTRB(compact ? 20 : 44, 24, 0, 120),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 24, bottom: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Discover', style: AppTheme.displaySmall),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: AppTextField(
                      hint: _activeKind == ServarrKind.movie
                          ? 'Search movies'
                          : 'Search shows',
                      onChanged: _setQuery,
                    ),
                  ),
                  const SizedBox(height: 16),
                  sc.ButtonGroup(
                    children: [
                      for (final kind in ServarrKind.values)
                        sc.Toggle(
                          value: _activeKind == kind,
                          onChanged: (_) => setState(() {
                            _activeKind = kind;
                          }),
                          child: Text(kind.label),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Reveal(
              child: _DiscoverRail(
                kind: _activeKind,
                query: _query,
                torrents: torrents,
                onOpen: (t) => _open(t, _activeKind),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiscoverRail extends ConsumerWidget {
  const _DiscoverRail({
    required this.kind,
    required this.query,
    required this.torrents,
    required this.onOpen,
  });

  final ServarrKind kind;
  final String query;
  final List<ServarrDownload>? torrents;
  final ValueChanged<ServarrTitle> onOpen;

  static const double _posterWidth = 190;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalized = query.trim();
    if (normalized.isNotEmpty) {
      final request = (kind: kind, query: normalized);
      final search = ref.watch(servarrSearchProvider(request));
      return search.when(
        loading: () => const _RailSkeleton(title: 'Results'),
        error: (_, _) => _RailUnavailable(
          title: 'Results',
          message: 'Search is unavailable right now.',
          onRetry: () => ref.invalidate(servarrSearchProvider(request)),
        ),
        data: (items) => items.isEmpty
            ? _RailUnavailable(
                title: 'Results',
                message: 'No matches for “$normalized”.',
                onRetry: () => ref.invalidate(servarrSearchProvider(request)),
              )
            : _shelf('Results', items),
      );
    }

    final discover = ref.watch(servarrDiscoverProvider(kind));
    return discover.when(
      loading: () => _RailSkeleton(title: kind.label),
      error: (_, _) => _RailUnavailable(
        title: kind.label,
        message:
            'Connect ${kind == ServarrKind.movie ? 'Radarr' : 'Sonarr'} to browse requests, or try again.',
        onRetry: () => ref.invalidate(servarrDiscoverProvider(kind)),
      ),
      data: (d) {
        if (d.items.isEmpty) {
          return _RailUnavailable(
            title: kind.label,
            message:
                'Connect ${kind == ServarrKind.movie ? 'Radarr' : 'Sonarr'} to browse requests, or try again.',
            onRetry: () => ref.invalidate(servarrDiscoverProvider(kind)),
          );
        }
        return _shelf(kind.label, d.items);
      },
    );
  }

  Widget _shelf(String title, List<ServarrTitle> items) => PosterShelf(
    title: title,
    leftInset: 0,
    itemCount: items.length,
    onActivate: (index) => onOpen(items[index]),
    itemBuilder: (_, index) => _card(items[index]),
  );

  Widget _card(ServarrTitle t) {
    final torrent = matchTorrent(t.title, torrents);
    final active = torrent != null && !torrent.isPaused;
    final pct = torrent?.percent ?? 0;
    final downloading = active && pct < 100;
    final subtitle = [
      t.year?.toString(),
      t.network,
    ].where((e) => e != null && e.isNotEmpty).join(' · ');

    return PosterCard(
      title: t.title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      imageUrl: t.posterUrl,
      rating: t.rating,
      width: _posterWidth,
      aspectRatio: 3 / 5,
      progress: downloading ? pct / 100 : null,
      onTap: () => onOpen(t),
    );
  }
}

/// A per-rail degraded state (empty/failed discover) — the shelf heading over a
/// quiet "unavailable" line, so one dead rail never fails the whole page.
class _RailUnavailable extends StatelessWidget {
  const _RailUnavailable({
    required this.title,
    required this.message,
    required this.onRetry,
  });
  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppTheme.headlineLarge.copyWith(color: wp.text)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(fontSize: 14, color: wp.dim),
                ),
              ),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton({required this.title});
  final String title;

  static const double _w = 190;
  static const double _h = _w * 5 / 3;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Text(
              title,
              style: AppTheme.headlineLarge.copyWith(color: wp.text),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: _h + 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  LoadingSkeleton(width: _w, height: _h, borderRadius: 12),
                  SizedBox(height: 10),
                  LoadingSkeleton(width: 120, height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailsSkeleton extends StatelessWidget {
  const _RailsSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(44, 24, 0, 120),
      children: [
        _RailSkeleton(title: 'Movies'),
        _RailSkeleton(title: 'Shows'),
      ],
    );
  }
}
