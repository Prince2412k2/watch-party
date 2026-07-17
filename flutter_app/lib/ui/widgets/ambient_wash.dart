import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../state/providers.dart';
import '../palette.dart';
import 'authed_image.dart';

/// The Jellyfin item whose artwork paints the ambient backdrop. The library and
/// detail screens set this on selection/focus (mirrors the web `--balanced-poster`
/// var Library.tsx drives); null falls back to the neutral radial gradient.
final ambientArtworkIdProvider = StateProvider<String?>((ref) => null);

/// The full-bleed blurred-artwork backdrop behind the shell.
///
/// Renders the selected title's backdrop image, blurred + desaturated + scaled,
/// under a darkening gradient — at an opacity that depends on the active theme
/// (1.0 balanced, .42 dark, .3 light; `.web-ambient` in styles.css). Purely
/// decorative: wrapped in [IgnorePointer] so it never gates content, and the
/// image is always fetched through the authed Jellyfin image pipeline
/// ([AuthedNetworkImage]), never a raw unauthenticated request.
///
/// Mount it as the lowest layer of the shell (a Positioned.fill in a Stack).
class AmbientWash extends ConsumerWidget {
  const AmbientWash({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    final itemId = ref.watch(ambientArtworkIdProvider);
    final api = ref.watch(apiClientProvider);
    final url = itemId == null
        ? null
        : api.imageUrl(itemId, type: ImageType.backdrop);

    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: wp.ambientOpacity,
        duration: const Duration(milliseconds: 350),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _Fallback(),
            if (url != null)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: _WashImage(
                  key: ValueKey(url),
                  url: url,
                  blur: wp.ambientBlur,
                  brightness: wp.ambientBrightness,
                ),
              ),
            const _WashGradient(),
          ],
        ),
      ),
    );
  }
}

class _WashImage extends StatelessWidget {
  const _WashImage({
    super.key,
    required this.url,
    required this.blur,
    required this.brightness,
  });

  final String url;
  final double blur;
  final double brightness;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 1.12,
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(_saturateBrightness(0.9, brightness)),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: AuthedNetworkImage(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// The neutral radial gradient shown before/without artwork
/// (`radial-gradient(circle at 30% 30%, #47505a, #17181b 64%)`).
class _Fallback extends StatelessWidget {
  const _Fallback();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.4, -0.4),
          radius: 1.1,
          colors: [Color(0xFF47505A), Color(0xFF17181B)],
          stops: [0.0, 0.64],
        ),
      ),
    );
  }
}

/// The darkening scrim over the artwork (`linear-gradient(130deg, …)`).
class _WashGradient extends StatelessWidget {
  const _WashGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1F08090B), Color(0x9408090B)],
        ),
      ),
    );
  }
}

/// CSS `saturate(s) brightness(b)` as a 4x5 colour matrix.
List<double> _saturateBrightness(double s, double b) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  double r0 = (1 - s) * lr + s, r1 = (1 - s) * lg, r2 = (1 - s) * lb;
  double g0 = (1 - s) * lr, g1 = (1 - s) * lg + s, g2 = (1 - s) * lb;
  double b0 = (1 - s) * lr, b1 = (1 - s) * lg, b2 = (1 - s) * lb + s;
  return [
    r0 * b, r1 * b, r2 * b, 0, 0, //
    g0 * b, g1 * b, g2 * b, 0, 0, //
    b0 * b, b1 * b, b2 * b, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}
