import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/api_client.dart';

void main() {
  test('DioApiClient loads the normalized trickplay manifest', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, '/api/library/items/movie/trickplay');
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'itemId': 'movie',
                'mediaSourceId': 'source',
                'width': 400,
                'height': 200,
                'tileWidth': 100,
                'tileHeight': 100,
                'thumbnailCount': 10,
                'intervalMs': 10000,
                'sheetCount': 2,
                'sheetUrlTemplate': '/sprites/{sheetIndex}.jpg',
              },
            ),
          );
        },
      ),
    );

    final manifest = await DioApiClient(dio: dio).trickplay('movie');

    expect(manifest.itemId, 'movie');
    expect(manifest.thumbnailCount, 10);
  });
}
