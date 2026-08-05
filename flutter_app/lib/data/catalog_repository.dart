import 'dart:convert';

import '../cache/catalog_cache_store.dart';
import '../models/models.dart';
import 'api_client.dart';

/// Emits persisted catalog data immediately, then refreshes it from the API.
class CatalogRepository {
  CatalogRepository({required this.api, this.cache});

  final ApiClient api;
  final CatalogCacheStore? cache;

  Stream<HomeData> home(String? namespace) => _watch(
    namespace: namespace,
    key: 'home',
    decode: (json) => HomeData.fromJson(json as Map<String, dynamic>),
    encode: (value) => value.toJson(),
    fetch: api.home,
  );

  Stream<List<LibraryItem>> items(String? namespace, {String? parentId}) =>
      _watch(
        namespace: namespace,
        key: 'items:${parentId ?? ''}',
        decode: _decodeItems,
        encode: _encodeItems,
        fetch: () => api.items(parentId: parentId),
      );

  Stream<List<LibraryItem>> latest(String? namespace, {String? parentId}) =>
      _watch(
        namespace: namespace,
        key: 'latest:${parentId ?? ''}',
        decode: _decodeItems,
        encode: _encodeItems,
        fetch: () => api.latest(parentId: parentId),
      );

  Stream<List<LibraryItem>> children(String? namespace, String itemId) =>
      _watch(
        namespace: namespace,
        key: 'children:$itemId',
        decode: _decodeItems,
        encode: _encodeItems,
        fetch: () => api.children(itemId),
      );

  Stream<LibraryItem> item(String? namespace, String id) => _watch(
    namespace: namespace,
    key: 'item:$id',
    decode: (json) => LibraryItem.fromJson(json as Map<String, dynamic>),
    encode: (value) => value.toJson(),
    fetch: () => api.item(id),
  );

  Stream<T> _watch<T>({
    required String? namespace,
    required String key,
    required T Function(dynamic json) decode,
    required dynamic Function(T value) encode,
    required Future<T> Function() fetch,
  }) async* {
    dynamic cachedJson;
    T? cached;
    if (namespace != null && cache != null) {
      cachedJson = await cache!.read(namespace, key);
      if (cachedJson != null) {
        try {
          final decoded = decode(cachedJson);
          cached = decoded;
          yield decoded;
        } catch (_) {
          cachedJson = null;
        }
      }
    }

    try {
      final fresh = await fetch();
      final freshJson = encode(fresh);
      // Persistence is best-effort and deliberately isolated: a cache write
      // that fails (full disk, unwritable support dir, a rename losing a race
      // with another writer) must never discard a good network result, which
      // is what a shared try/catch with the fetch did — the caller was handed
      // a stale-or-error stream even though the request had succeeded.
      if (namespace != null && cache != null) {
        try {
          await cache!.write(namespace, key, freshJson);
        } catch (_) {}
      }
      if (cached == null || jsonEncode(cachedJson) != jsonEncode(freshJson)) {
        yield fresh;
      }
    } catch (_) {
      if (cached == null) rethrow;
    }
  }
}

List<LibraryItem> _decodeItems(dynamic json) => (json as List)
    .map((item) => LibraryItem.fromJson(item as Map<String, dynamic>))
    .toList();

List<Map<String, dynamic>> _encodeItems(List<LibraryItem> items) =>
    items.map((item) => item.toJson()).toList();
