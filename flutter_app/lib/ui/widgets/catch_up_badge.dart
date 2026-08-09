// "Catching up ▶▶" — the player saying out loud that it is adjusting your speed.
//
// The sync engine closes small gaps by nudging playbackRate rather than jumping
// the picture, because a jump costs you the second you were watching and a nudge
// costs nothing. The band it will do that across is wide enough now to ride out
// a real buffering stumble, which means the adjustment lasts long enough to be
// noticed — roughly ten seconds of catching up per second of drift.
//
// Something that alters the speed of your film without telling you reads as a
// fault when it IS noticed. Told what is happening, the same ten seconds reads
// as the app working. That is the entire job of this widget.
//
// It renders nothing when the rate is 1.0, which is nearly always.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/state.dart';
import '../../sync/sync_engine.dart';
import '../ui.dart';

class CatchUpBadge extends ConsumerWidget {
  const CatchUpBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(catchUpProvider).value ?? CatchUp.idle;

    return AnimatedSwitcher(
      duration: AppMotion.snap,
      switchInCurve: AppMotion.emphasized,
      child: state.active
          // Keyed on direction so switching from behind to ahead animates as a
          // replacement rather than silently relabelling in place.
          ? _Pill(behind: state.behind, key: ValueKey(state.behind))
          : const SizedBox.shrink(),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.behind});

  /// Behind the room and being sped up. The other direction is being held back,
  /// which is the same mechanism but not the same news — "catching up" would be
  /// a lie, and lying about which way is worse than saying nothing.
  final bool behind;

  @override
  Widget build(BuildContext context) {
    final label = behind ? 'CATCHING UP' : 'EASING BACK';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC17181B),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.line2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontFamily: AppFonts.mono,
                color: AppColors.dim,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 6),
            _Chevrons(reversed: !behind),
          ],
        ),
      ),
    );
  }
}

/// Two chevrons that pulse in sequence, so the badge reads as motion rather
/// than as a warning sitting on the picture. Pointing the way playback is
/// being pushed: forward while catching up, back while easing off.
class _Chevrons extends StatefulWidget {
  const _Chevrons({required this.reversed});

  final bool reversed;

  @override
  State<_Chevrons> createState() => _ChevronsState();
}

class _ChevronsState extends State<_Chevrons>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.reversed
        ? Icons.keyboard_arrow_left
        : Icons.keyboard_arrow_right;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 2; i++)
              Opacity(
                // Each chevron leads the next by a third of the cycle.
                opacity: _opacityFor(i),
                child: Transform.translate(
                  // Overlapped so the pair reads as one arrow, not two glyphs.
                  offset: Offset(i * -5.0 * (widget.reversed ? -1 : 1), 0),
                  child: Icon(icon, size: 14, color: AppColors.text),
                ),
              ),
          ],
        );
      },
    );
  }

  double _opacityFor(int index) {
    final phase = (_c.value - index * 0.33) % 1.0;
    // A short bright window, then a long dim one: a travelling highlight rather
    // than two independently blinking arrows.
    return phase < 0.5 ? 0.35 + (1 - phase * 2) * 0.65 : 0.35;
  }
}
