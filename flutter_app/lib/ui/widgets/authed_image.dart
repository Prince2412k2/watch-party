import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../state/providers.dart';

/// `Image.network` that attaches the current session cookie.
///
/// `Image.network` runs on its own HTTP client, separate from the app's dio
/// instance — so it never carries the cookie `dio_cookie_manager` attaches to
/// regular API calls. Every image the backend serves (posters, backdrops,
/// servarr artwork) lives behind `requireAuth`, so without this the request
/// 401s and only `errorBuilder`'s fallback ever renders.
class AuthedNetworkImage extends ConsumerStatefulWidget {
  const AuthedNetworkImage(
    this.url, {
    super.key,
    this.fit,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String url;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  @override
  ConsumerState<AuthedNetworkImage> createState() => _AuthedNetworkImageState();
}

class _AuthedNetworkImageState extends ConsumerState<AuthedNetworkImage> {
  StreamSubscription<Uint8List>? _subscription;
  Uint8List? _bytes;
  Object? _error;
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AuthedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  void _load() {
    final generation = ++_generation;
    _subscription?.cancel();
    _bytes = null;
    _error = null;
    final cache = ref.read(artworkCacheProvider);
    if (cache == null) return;
    _subscription = cache
        .load(widget.url)
        .listen(
      (bytes) {
        if (mounted && generation == _generation) {
          setState(() => _bytes = bytes);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (mounted && generation == _generation) {
          setState(() => _error = error);
        }
          },
        );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(apiClientProvider);
    final cache = ref.watch(artworkCacheProvider);
    if (cache != null) {
      if (_bytes != null) {
        return Image.memory(
          _bytes!,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: widget.errorBuilder,
        );
      }
      if (_error != null && widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error!, StackTrace.current);
      }
      return widget.loadingBuilder?.call(
            context,
            const SizedBox.expand(),
            null,
          ) ??
          const SizedBox.expand();
    }
    final cookie = client is DioApiClient ? client.cookieHeader : null;
    return Image.network(
      widget.url,
      fit: widget.fit,
      errorBuilder: widget.errorBuilder,
      loadingBuilder: widget.loadingBuilder,
      headers: cookie == null ? null : {'Cookie': cookie},
    );
  }
}
