import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/data/api_client.dart';
import 'package:watchparty/player/playback_failure.dart';

void main() {
  test('network and authorization failures are retryable', () {
    expect(
      classifyPlaybackFailure(const SocketException('connection reset')).kind,
      PlaybackFailureKind.network,
    );
    expect(classifyPlaybackFailure(TimeoutException('slow')).retryable, isTrue);
    expect(
      classifyPlaybackFailure(ApiException('stream', 401, 'expired')).kind,
      PlaybackFailureKind.authorization,
    );
  });

  test('decode failures are explicit and never auto-retried', () {
    final failure = classifyPlaybackFailure(
      'hardware decoder failed codec init',
    );
    expect(failure.kind, PlaybackFailureKind.decode);
    expect(failure.retryable, isFalse);
    expect(failure.message, contains('decoded'));
  });
}
