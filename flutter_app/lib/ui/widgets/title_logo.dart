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

/// The tag that carries a title's logo between the browse stage and the detail
/// page. One per item, so the two ends find each other and nothing else.
String titleLogoHeroTag(String itemId) => 'logo-$itemId';

/// The logo where it stands on its own beside the copy, rather than inside it.
///
/// Renders NOTHING when the item has no logo. The written title in the copy
/// column is already saying the name; a second copy of it in the app's own
/// face, off to one side, would just be the same words twice.
///
/// Tagged, so that opening the title flies this artwork into the heading slot
/// on the detail page instead of cutting to it.
class AsideTitleLogo extends StatelessWidget {
  const AsideTitleLogo({
    super.key,
    required this.itemId,
    required this.url,
    required this.maxHeightPx,
  });

  final String? itemId;
  final String? url;
  final double maxHeightPx;

  @override
  Widget build(BuildContext context) {
    if (url == null || itemId == null) return const SizedBox.shrink();
    return Hero(
      tag: titleLogoHeroTag(itemId!),
      child: TitleLogo(
        url: url,
        maxHeightPx: maxHeightPx,
        alignment: Alignment.center,
        child: const SizedBox.shrink(),
      ),
    );
  }
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
    this.alignment = AlignmentDirectional.centerStart,
  });

  /// Logo artwork, or null to render [child] without asking the network.
  final String? url;

  /// Cap on the logo's height. Width follows the artwork's own aspect, held to
  /// whatever the surrounding column allows.
  final double maxHeightPx;

  /// The text heading, shown when there is no logo.
  final Widget child;

  /// Where the artwork sits in the width it is given. Start where it stands in
  /// for a heading; centred where it stands on its own beside the copy.
  final AlignmentGeometry alignment;

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
      alignment: alignment,
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
