import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analog/chrome/analog_command_palette.dart';
import '../models/models.dart';
import '../state/state.dart';
import 'widgets/nav_rail.dart' show NavDestination;

/// The app command palette (Ctrl/Cmd-K and `/`). An [showAnalogCommandPalette]
/// modal that fuzzy-searches the library — reusing [libraryProvider] read-only
/// — and offers quick-nav to every shell destination.
///
/// Kept decoupled from the router: the caller supplies the shell [destinations]
/// and an [onNavigate] callback, so this can be opened both from the shell
/// (below the Navigator) and from the app-wide title bar (above it, via the
/// root navigator context).
Future<void> showCommandPalette({
  required BuildContext context,
  required WidgetRef ref,
  required List<NavDestination> destinations,
  required void Function(String route) onNavigate,
}) {
  return showAnalogCommandPalette(
    context: context,
    hint: 'Search your library',
    // Snappier than half a second — this is a local list, not a network
    // search, so results should feel instant.
    debounce: const Duration(milliseconds: 140),
    results: (query) => _results(context, ref, destinations, onNavigate, query),
  );
}

/// Yields results in two passes (the palette *accumulates* successive yields):
/// the quick-nav list first (instant), then the library matches once the flat
/// library resolves. Emitting deltas — never the full list twice — keeps the
/// accumulator from duplicating the nav category.
Stream<List<AnalogCommandCategory>> _results(
  BuildContext context,
  WidgetRef ref,
  List<NavDestination> destinations,
  void Function(String route) onNavigate,
  String? query,
) async* {
  final q = (query ?? '').trim();

  void run(String route) {
    Navigator.of(context).pop();
    onNavigate(route);
  }

  // Pass 1 — quick navigation (always available, filtered by the query).
  final navItems = <AnalogCommandItem>[
    for (final d in destinations)
      if (_fuzzyScore(q, d.label) != null)
        AnalogCommandItem(
          icon: d.icon,
          label: d.label,
          onSelected: () => run(d.route),
        ),
  ];
  yield [
    if (navItems.isNotEmpty)
      AnalogCommandCategory(title: 'Go to', items: navItems),
  ];

  // Pass 2 — library search only kicks in once the user types.
  if (q.isEmpty) return;
  try {
    final items = await ref.read(libraryProvider(null).future);
    final ranked = <(int, LibraryItem)>[];
    for (final item in items) {
      final score = _fuzzyScore(q, item.name);
      if (score != null) ranked.add((score, item));
    }
    ranked.sort((a, b) => a.$1.compareTo(b.$1));

    final libItems = <AnalogCommandItem>[
      for (final (_, item) in ranked.take(20))
        AnalogCommandItem(
          icon: _iconForType(item.type),
          label: item.name,
          trailing: item.productionYear?.toString(),
          onSelected: () => run('/detail/${item.id}'),
        ),
    ];
    yield [
      if (libItems.isNotEmpty)
        AnalogCommandCategory(title: 'Library', items: libItems),
    ];
  } catch (_) {
    // Offline or signed out: the library isn't reachable — the quick-nav list
    // still stands, so the palette stays useful.
  }
}

/// A small fuzzy matcher. Returns `null` for no match, otherwise a rank score
/// (lower is better): substring hits score by position (prefix = best);
/// subsequence hits (all query chars in order, with gaps) sort after every
/// substring hit. An empty query matches everything.
int? _fuzzyScore(String query, String target) {
  if (query.isEmpty) return 0;
  final q = query.toLowerCase();
  final t = target.toLowerCase();

  final idx = t.indexOf(q);
  if (idx >= 0) return idx;

  var cursor = 0;
  var gaps = 0;
  for (var i = 0; i < q.length; i++) {
    final found = t.indexOf(q[i], cursor);
    if (found < 0) return null;
    gaps += found - cursor;
    cursor = found + 1;
  }
  return 1000 + gaps;
}

IconData _iconForType(String? type) => switch (type) {
  'Movie' => Icons.movie_outlined,
  'Series' => Icons.live_tv_outlined,
  'Episode' => Icons.smart_display_outlined,
  _ => Icons.play_circle_outline,
};
