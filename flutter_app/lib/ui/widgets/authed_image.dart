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
    this.filterQuality,
    this.cacheWidth,
    this.cacheHeight,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String url;
  final BoxFit? fit;
  final FilterQuality? filterQuality;
  final int? cacheWidth;
  final int? cacheHeight;
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
    final cache = ref.read(artworkCacheProvider);
    _bytes = cache?.peek(widget.url);
    _error = null;
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
          filterQuality: widget.filterQuality ?? FilterQuality.medium,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
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
    // This branch only runs when no artwork cache is installed, which never
    // happens in production (main.dart always builds one) — but if it ever
    // did, the cookie must still never follow the url to a third-party host.
    // Mirrors the same-origin check in ApiClient.downloadDesktopArtifact.
    final cookie = client is DioApiClient && _isSameOrigin(widget.url, client.baseUrl)
        ? client.cookieHeader
        : null;
    return Image.network(
      widget.url,
      fit: widget.fit,
      filterQuality: widget.filterQuality ?? FilterQuality.medium,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      errorBuilder: widget.errorBuilder,
      loadingBuilder: widget.loadingBuilder,
      headers: cookie == null ? null : {'Cookie': cookie},
    );
  }
}

/// True when `url` is either a relative path (resolves against the API
/// origin by definition) or an absolute URL on the exact same
/// scheme+host+port as [baseUrl]. Anything else is a third-party host the
/// session cookie must never reach.
bool _isSameOrigin(String url, String baseUrl) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (!uri.hasScheme && !uri.hasAuthority) return true;
  final base = Uri.tryParse(baseUrl);
  if (base == null) return false;
  return uri.hasScheme &&
      uri.scheme == base.scheme &&
      uri.host == base.host &&
      uri.port == base.port;
}
