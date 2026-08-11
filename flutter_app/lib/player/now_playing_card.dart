import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../state/library_provider.dart';
import '../state/providers.dart';
import '../ui/theme.dart';
import '../ui/widgets/authed_image.dart';

/// The card that covers the picture while the next title loads.
///
/// A film swapped underneath you is the most disorienting thing a shared room
/// can do — the host changes title and your screen goes black, then something
/// else is playing. So the change announces itself: the incoming title's
/// backdrop, its poster, its name, held for a beat while the file opens behind
/// it. What was jarring becomes the moment the room turns over.
///
/// Sized off the frame it is given, so the same card works full-window and in
/// the corner tile — where the poster is dropped rather than shrunk to a stamp.
class NowPlayingCard extends ConsumerWidget {
  const NowPlayingCard({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(apiClientProvider);
    final title = ref.watch(itemDetailProvider(itemId)).valueOrNull?.name;

    return Stack(
      fit: StackFit.expand,
      children: [
        AuthedNetworkImage(
          api.imageUrl(itemId, type: ImageType.backdrop),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
        ),
        // The backdrop is scenery here, not the subject: it carries the mood
        // and the poster carries the identity, so it sits well back.
        const Positioned.fill(child: ColoredBox(color: Color(0xD90A0A0A))),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 260;
            final posterHeight = (constraints.maxHeight * 0.46).clamp(
              120.0,
              300.0,
            );
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!compact) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox(
                        height: posterHeight,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: AuthedNetworkImage(
                            api.imageUrl(itemId),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const ColoredBox(color: Color(0xFF1A1A1A)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  Text(
                    'NOW PLAYING',
                    style: AppTheme.mono.copyWith(
                      color: Colors.white70,
                      fontSize: compact ? 8 : 10,
                      letterSpacing: 2.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (title != null) ...[
                    SizedBox(height: compact ? 4 : 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (compact
                                    ? AppTheme.titleMedium
                                    : AppTheme.displaySmall)
                                .copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
