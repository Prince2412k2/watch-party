import 'dart:async';
import 'dart:io';

import '../data/api_client.dart';

enum PlaybackFailureKind { network, authorization, decode, unknown }

class PlaybackFailure {
  const PlaybackFailure(this.kind, this.message);

  final PlaybackFailureKind kind;
  final String message;

  bool get retryable =>
      kind == PlaybackFailureKind.network ||
      kind == PlaybackFailureKind.authorization;
}

PlaybackFailure classifyPlaybackFailure(Object error) {
  if (error is SocketException || error is TimeoutException) {
    return const PlaybackFailure(
      PlaybackFailureKind.network,
      'The network connection was interrupted.',
    );
  }
  if (error is ApiException) {
    if (error.statusCode == 401 || error.statusCode == 403) {
      return const PlaybackFailure(
        PlaybackFailureKind.authorization,
        'The stream authorization expired.',
      );
    }
    if (error.statusCode == 0 || error.statusCode >= 500) {
      return const PlaybackFailure(
        PlaybackFailureKind.network,
        'The media server could not be reached.',
      );
    }
  }

  final text = error.toString().toLowerCase();
  if (_containsAny(text, const [
    'network', 'connection', 'timed out', 'timeout', 'socket',
    'http error', 'tls', 'dns', 'broken pipe',
  ])) {
    return const PlaybackFailure(
      PlaybackFailureKind.network,
      'The network connection was interrupted.',
    );
  }
  if (_containsAny(text, const ['401', '403', 'unauthorized', 'forbidden'])) {
    return const PlaybackFailure(
      PlaybackFailureKind.authorization,
      'The stream authorization expired.',
    );
  }
  if (_containsAny(text, const [
    'decode', 'decoder', 'codec', 'hardware acceleration', 'video output',
    'unsupported format', 'unsupported profile',
  ])) {
    return const PlaybackFailure(
      PlaybackFailureKind.decode,
      'This video stream could not be decoded.',
    );
  }
  return const PlaybackFailure(
    PlaybackFailureKind.unknown,
    'The video stream could not be played.',
  );
}

bool _containsAny(String text, List<String> terms) =>
    terms.any(text.contains);
