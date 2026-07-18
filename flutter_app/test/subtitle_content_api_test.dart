import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/models/playback_info.dart';

void main() {
  test(
    'DioApiClient forwards the selected media source for native playback',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/api/library/native/stream-url/movie');
            expect(options.queryParameters, {
              'purpose': 'stream',
              'mediaSourceId': 'source-4k',
            });
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'url': 'https://stream.test/file', 'expiresAt': 1},
              ),
            );
          },
        ),
      );

      await DioApiClient(
        dio: dio,
      ).nativeStreamUrl('movie', mediaSourceId: 'source-4k');
    },
  );

  test('DioApiClient requests subtitle content as plain text', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, '/api/library/items/movie/subtitles/4/content');
          expect(options.responseType, ResponseType.plain);
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: '1\n00:00:01,000 --> 00:00:02,000\nHello\n',
            ),
          );
        },
      ),
    );

    final content = await DioApiClient(dio: dio).subtitleContent('movie', 4);

    expect(content, contains('Hello'));
  });

  test('DioApiClient uploads subtitle bytes with filename metadata', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.path, '/api/library/items/movie/subtitles');
          expect(options.headers[Headers.contentLengthHeader], 3);
          expect(options.headers['Content-Type'], 'application/octet-stream');
          expect(options.headers['X-Subtitle-Filename'], 'English%20SDH.srt');
          handler.resolve(Response(requestOptions: options, statusCode: 201));
        },
      ),
    );

    await DioApiClient(
      dio: dio,
    ).uploadSubtitle('movie', [1, 2, 3], 'English SDH.srt');
  });

  test('PlaybackInfo preserves external subtitle metadata', () {
    final info = PlaybackInfo.fromJson({
      'subtitleStreams': [
        {
          'index': 7,
          'displayTitle': 'English SDH',
          'language': 'eng',
          'codec': 'srt',
          'isExternal': true,
          'isDefault': true,
        },
      ],
    });

    expect(info.subtitleStreams.single.index, 7);
    expect(info.subtitleStreams.single.isExternal, isTrue);
    expect(info.subtitleStreams.single.isDefault, isTrue);
  });
}
