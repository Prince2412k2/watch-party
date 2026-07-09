import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../models/models.dart';
import 'providers.dart';

/// Home/browse data (PLAN §3.8). Async providers over [apiClientProvider]. E3
/// enriches (sections, continue-watching, filters); the shapes are frozen.

/// The aggregated home payload (views + resume + next-up).
final homeProvider = FutureProvider<HomeData>((ref) async {
  return ref.read(apiClientProvider).home();
});

/// The flat library list, optionally scoped to a parent (library view) id.
final libraryProvider =
    FutureProvider.family<List<LibraryItem>, String?>((ref, parentId) async {
  return ref.read(apiClientProvider).items(parentId: parentId);
});

/// A single title's full detail.
final itemDetailProvider =
    FutureProvider.family<LibraryItem, String>((ref, id) async {
  return ref.read(apiClientProvider).item(id);
});

/// Search results for a query.
final searchProvider =
    FutureProvider.family<List<LibraryItem>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  return ref.read(apiClientProvider).search(query);
});
