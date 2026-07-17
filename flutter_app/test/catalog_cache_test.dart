import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/cache/catalog_cache_store.dart';
import 'package:watchparty/data/catalog_repository.dart';
import 'package:watchparty/data/mock_api_client.dart';
import 'package:watchparty/models/models.dart';

class _CatalogApi extends MockApiClient {
  _CatalogApi(this.result);

  final List<LibraryItem> result;

  @override
  Future<List<LibraryItem>> items({String? parentId}) async => result;
}

void main() {
  test('catalog emits persisted data before refreshed API data', () async {
    final directory = await Directory.systemTemp.createTemp('catalog-cache-');
    addTearDown(() => directory.delete(recursive: true));
    final store = CatalogCacheStore(directory);
    const namespace = 'server|user';
    const cached = LibraryItem(id: 'cached', name: 'Cached', type: 'Movie');
    const fresh = LibraryItem(id: 'fresh', name: 'Fresh', type: 'Movie');
    await store.write(namespace, 'items:', [cached.toJson()]);

    final repository = CatalogRepository(
      api: _CatalogApi(const [fresh]),
      cache: store,
    );
    final emissions = await repository.items(namespace).toList();

    expect(emissions.map((items) => items.single.id), ['cached', 'fresh']);

    final reloaded = CatalogRepository(
      api: _CatalogApi(const [fresh]),
      cache: CatalogCacheStore(directory),
    );
    final nextStartup = await reloaded.items(namespace).first;
    expect(nextStartup.single.id, 'fresh');
  });

  test('catalog namespaces do not share private data', () async {
    final directory = await Directory.systemTemp.createTemp('catalog-cache-');
    addTearDown(() => directory.delete(recursive: true));
    final store = CatalogCacheStore(directory);
    await store.write('server|alice', 'home', {'views': []});

    expect(await store.read('server|alice', 'home'), isNotNull);
    expect(await store.read('server|bob', 'home'), isNull);
  });
}
