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
class AuthedNetworkImage extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(apiClientProvider);
    final cookie = client is DioApiClient ? client.cookieHeader : null;
    return Image.network(
      url,
      fit: fit,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
      headers: cookie == null ? null : {'Cookie': cookie},
    );
  }
}
