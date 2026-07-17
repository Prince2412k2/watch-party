import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/state.dart';
import '../palette.dart';
import 'party_widget.dart';

/// The bottom-right watch-party control (`.web-party-float` / `.web-party-button`,
/// styles.css:370-397). A 46px circular popcorn button that toggles the
/// expandable [PartyWidget] above it. It carries a green live dot while a party
/// session is active and a red badge counting guests awaiting approval; the menu
/// auto-opens for a host the moment someone is waiting (mirrors the web effect),
/// and a tap outside closes it via [TapRegion].
///
/// The popcorn glyph is intentionally always dark (`#202126`) regardless of
/// theme — it is a fixed brand mark, not a theme surface.
class PopcornControl extends ConsumerStatefulWidget {
  const PopcornControl({super.key});

  @override
  ConsumerState<PopcornControl> createState() => _PopcornControlState();
}

class _PopcornControlState extends ConsumerState<PopcornControl> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(partyWaitingProvider, (_, next) {
      if (next.isNotEmpty &&
          !_open &&
          ref.read(partyProvider.notifier).isHost) {
        setState(() => _open = true);
      }
    });

    final live = ref.watch(partyProvider) != null;
    final waiting = ref.watch(partyWaitingProvider).length;

    return TapRegion(
      onTapOutside: (_) {
        if (_open) setState(() => _open = false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (_open) ...[const PartyWidget(), const SizedBox(height: 10)],
          _PopcornButton(
            live: live,
            waiting: waiting,
            onTap: () => setState(() => _open = !_open),
          ),
        ],
      ),
    );
  }
}

class _PopcornButton extends StatefulWidget {
  const _PopcornButton({
    required this.live,
    required this.waiting,
    required this.onTap,
  });

  final bool live;
  final int waiting;
  final VoidCallback onTap;

  @override
  State<_PopcornButton> createState() => _PopcornButtonState();
}

class _PopcornButtonState extends State<_PopcornButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFF2A2C31) : const Color(0xFF202126),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(
                color: Color(0x38000000),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Image.asset('assets/popcorn.png', width: 34, height: 34),
              if (widget.live)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: kPartyLive,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF202126),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              if (widget.waiting > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kSemanticRed,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${widget.waiting}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
