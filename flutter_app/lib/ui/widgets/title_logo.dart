import 'package:flutter/widgets.dart';

import '../../data/api_client.dart';
import '../../models/models.dart';
import 'authed_image.dart';

/// [item]'s logo artwork, or null when the library has no `Logo` image for it.
///
/// Checked against the tag rather than fetched hopefully: without it every
/// title that has no logo — every episode, most series — would spend a request
/// to find that out, and hold a blank heading until the 404 came back.
String? titleLogoUrl(ApiClient api, LibraryItem item) {
  final tag = item.imageTags?['Logo'];
  if (tag == null) return null;
  return api.imageUrl(item.id, type: ImageType.logo, tag: tag);
}

/// A title's logo artwork, standing in for the text heading.
///
/// A film's logo is its name as the film itself sets it — the typeface, the
/// spacing, the mark. It reads as the title far faster than the same words in
/// the app's own face do, which is the whole point of showing it where the
/// heading used to be.
///
/// The text is not dropped, it is the fallback: [child] renders whenever there
/// is no logo to show. That covers three cases with one path — no `Logo` image
/// on the item ([url] null), a tag that no longer resolves, and artwork that
/// fails to decode. A blank heading is the one outcome this must never produce.
class TitleLogo extends StatelessWidget {
  const TitleLogo({
    super.key,
    required this.url,
    required this.maxHeightPx,
    required this.child,
  });

  /// Logo artwork, or null to render [child] without asking the network.
  final String? url;

  /// Cap on the logo's height. Width follows the artwork's own aspect, held to
  /// whatever the surrounding column allows.
  final double maxHeightPx;

  /// The text heading, shown when there is no logo.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (url == null) return child;

    // Decoding to the display height rather than the source's own gives the
    // image its intrinsic size for free: it lays out at maxHeightPx tall, and
    // narrower than the column unless the artwork is extremely wide, in which
    // case `contain` scales it down instead of overflowing.
    final decodeHeight =
        (maxHeightPx * MediaQuery.devicePixelRatioOf(context)).round();

    // The align is load-bearing, not cosmetic. Some of these headings sit in an
    // `Expanded`, which hands down a TIGHT width — an image told exactly how
    // wide to be takes that width and derives its height from it, which for a
    // wide logo is a letterboxed slab several hundred pixels tall. Aligning
    // first re-loosens the width so the artwork keeps its own size, and
    // `heightFactor` shrink-wraps the height so this still works inside a
    // vertically unbounded column.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      heightFactor: 1,
      child: AuthedNetworkImage(
        url!,
        fit: BoxFit.contain,
        cacheHeight: decodeHeight,
        errorBuilder: (_, _, _) => child,
        // Holds the heading's room while the bytes arrive, so the copy below
        // does not jump once they land. Not `SizedBox.expand`: nothing here
        // bounds the height.
        loadingBuilder: (_, _, _) => SizedBox(height: maxHeightPx),
      ),
    );
  }
}
