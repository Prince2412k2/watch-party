import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/models/playback_info.dart';

void main() {
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
