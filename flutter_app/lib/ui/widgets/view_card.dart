import 'package:flutter/material.dart';

import '../palette.dart';
import 'authed_image.dart';

/// A 16:9 library tile — the "Libraries" rail primitive (web `ViewCard`,
/// Library.tsx). Cover art dimmed under a left-dark gradient, with an
/// icon + name overlaid bottom-left.
///
/// Hover brightens the art and strengthens the shadow; per the design guide it
/// never translates the card upward. [onHover] lets a shelf drive the ambient
/// wash off the card the pointer is over.
class ViewCard extends StatefulWidget {
  const ViewCard({
    super.key,
    required this.name,
    this.imageUrl,
    this.icon = Icons.folder_outlined,
    this.onTap,
    this.onHover,
    this.width = 300,
  });

  final String name;
  final String? imageUrl;
  final IconData icon;
  final VoidCallback? onTap;
  final VoidCallback? onHover;
  final double width;

  @override
  State<ViewCard> createState() => _ViewCardState();
}

class _ViewCardState extends State<ViewCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;

    return SizedBox(
      width: widget.width,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hover = true);
          widget.onHover?.call();
        },
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: wp.surface,
              boxShadow: _hover ? wp.posterShadowHover : wp.posterShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.imageUrl != null)
                      AnimatedOpacity(
                        opacity: _hover ? 1 : 0.74,
                        duration: const Duration(milliseconds: 250),
                        child: AuthedNetworkImage(
                          widget.imageUrl!,
                          fit: BoxFit.cover,
                          cacheWidth:
                              (widget.width *
                                      MediaQuery.devicePixelRatioOf(context))
                                  .round(),
                          errorBuilder: (_, _, _) =>
                              ColoredBox(color: wp.surface2),
                        ),
                      )
                    else
                      ColoredBox(color: wp.surface2),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [Color(0xB8000000), Color(0x1A000000)],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 13),
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(widget.icon, size: 20, color: Colors.white),
                            const SizedBox(width: 9),
                            Flexible(
                              child: Text(
                                widget.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
