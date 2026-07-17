import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

        return ListView(
          padding: const EdgeInsets.fromLTRB(44, 24, 0, 120),
          children: [
            Reveal(
              child: _DiscoverRail(
                kind: ServarrKind.movie,
                torrents: torrents,
                onOpen: (t) => _open(t, ServarrKind.movie),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Reveal(
              delay: AppMotion.stagger,
              child: _DiscoverRail(
                kind: ServarrKind.series,
                torrents: torrents,
                onOpen: (t) => _open(t, ServarrKind.series),
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
    required this.torrents,
    required this.onOpen,
  });

  final ServarrKind kind;
  final List<ServarrDownload>? torrents;
  final ValueChanged<ServarrTitle> onOpen;

  static const double _posterWidth = 190;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discover = ref.watch(servarrDiscoverProvider(kind));
    return discover.when(
      loading: () => _RailSkeleton(title: kind.label),
      error: (_, _) => _RailUnavailable(title: kind.label),
      data: (d) {
        if (d.items.isEmpty) return _RailUnavailable(title: kind.label);
        return PosterShelf(
          title: kind.label,
          leftInset: 0,
          children: [
            for (var i = 0; i < d.items.length; i++)
              _card(d.items[i], first: i == 0),
          ],
        );
      },
    );
  }

  Widget _card(ServarrTitle t, {required bool first}) {
    final torrent = matchTorrent(t.title, torrents);
    final active = torrent != null && !torrent.isPaused;
    final pct = torrent?.percent ?? 0;
    final downloading = active && pct < 100;
    final subtitle = [t.year?.toString(), t.network]
        .where((e) => e != null && e.isNotEmpty)
        .join(' · ');

    return PosterCard(
      title: t.title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      imageUrl: t.posterUrl,
      rating: t.rating,
      width: _posterWidth,
      aspectRatio: 3 / 5,
      emphasized: first,
      progress: downloading ? pct / 100 : null,
      onTap: () => onOpen(t),
    );
  }
}

/// A per-rail degraded state (empty/failed discover) — the shelf heading over a
/// quiet "unavailable" line, so one dead rail never fails the whole page.
class _RailUnavailable extends StatelessWidget {
  const _RailUnavailable({required this.title});
  final String title;

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
          Text(
            'This row is unavailable right now.',
            style: TextStyle(fontSize: 14, color: wp.dim),
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
