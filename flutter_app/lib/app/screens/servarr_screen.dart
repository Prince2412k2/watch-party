import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/chrome/chrome.dart';
import '../../analog/stage_layout.dart';
import '../../analog/widgets/analog_rail.dart';
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

        return ListView(
          padding: const EdgeInsets.fromLTRB(44, 24, 0, 120),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 24, bottom: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Discover', style: AppTheme.displaySmall),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: 440,
                    child: AppTextField(
                      hint: _activeKind == ServarrKind.movie
                          ? 'Search movies'
                          : 'Search shows',
                      onChanged: _setQuery,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AnalogSegmented<ServarrKind>(
                    semanticLabel: 'Discover',
                    value: _activeKind,
                    segments: [
                      for (final kind in ServarrKind.values)
                        AnalogSegment(value: kind, label: kind.label),
                    ],
                    onChanged: (kind) => setState(() => _activeKind = kind),
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

/// Discover's row of titles.
///
/// The same rail the Movies and Shows tabs run — [AnalogRail], with its fixed
/// cursor, the row travelling underneath it, the scale falloff and the settle.
/// It used to be a [PosterShelf]: a plain scroller with a moving cursor, which
/// meant the two halves of the app that both show a row of posters answered
/// the arrow keys differently and looked different doing it. The rail takes a
/// list of [AnalogRailItem]s and does not care where they came from, so there
/// was never a reason for Discover to have its own.
class _DiscoverRail extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<_DiscoverRail> createState() => _DiscoverRailState();
}

class _DiscoverRailState extends ConsumerState<_DiscoverRail> {
  int _selected = 0;

  ServarrKind get kind => widget.kind;
  String get query => widget.query;

  @override
  Widget build(BuildContext context) {
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

  Widget _shelf(String title, List<ServarrTitle> items) {
    final media = MediaQuery.of(context);
    final size = stageLayout(media.size.width, media.size.height, false).size;
    final selection = _selected.clamp(0, items.isEmpty ? 0 : items.length - 1);

    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTheme.headlineLarge.copyWith(color: context.wp.text),
          ),
          const SizedBox(height: 20),
          AnalogRail(
            items: [for (final t in items) _railItem(t)],
            selection: selection,
            size: size,
            motion: motionProfile(media.disableAnimations),
            onSelect: (i) => setState(() => _selected = i),
            onActivate: (i) => widget.onOpen(items[i]),
            emptyLabel: 'Nothing here yet',
          ),
        ],
      ),
    );
  }

  AnalogRailItem _railItem(ServarrTitle t) {
    final torrent = matchTorrent(t.title, widget.torrents);
    final active = torrent != null && !torrent.isPaused;
    final pct = torrent?.percent ?? 0;
    final downloading = active && pct < 100;
    final subtitle = [
      t.year?.toString(),
      t.network,
    ].where((e) => e != null && e.isNotEmpty).join(' · ');

    return AnalogRailItem(
      // A Discover title has no library id — tmdb/tvdb is the only stable one
      // it has, and the rail only needs it to tell rows apart.
      id: '${t.tmdbId ?? t.tvdbId ?? t.title}',
      label: t.title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      imageUrl: t.posterUrl,
      progress: downloading ? pct / 100 : null,
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
              AnalogButton(
                label: 'Retry',
                icon: Icons.refresh,
                tone: AnalogButtonTone.ghost,
                dense: true,
                onPressed: onRetry,
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
