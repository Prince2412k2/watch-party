import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../state/profile_provider.dart';
import '../../state/providers.dart';
import '../palette.dart';
import '../tokens.dart';

/// Somebody's face.
///
/// The web client draws these itself from an asset package in its bundle;
/// humation is a JavaScript renderer, so here the server draws it and we
/// display the SVG. That means an avatar needs the network, unlike on the web
/// — so until it arrives, and whenever it can't be fetched at all, this falls
/// back to the initials the app showed before profiles existed. A missing
/// avatar is never a missing person.
class AvatarView extends ConsumerStatefulWidget {
  const AvatarView({
    super.key,
    required this.userId,
    required this.name,
    this.size = 36,
  });

  final String userId;
  final String name;
  final double size;

  @override
  ConsumerState<AvatarView> createState() => _AvatarViewState();
}

class _AvatarViewState extends ConsumerState<AvatarView> {
  // Shared across every avatar on screen: a party redraws constantly and these
  // are tens of kilobytes each, so refetching per rebuild would be wasteful.
  // Dropped wholesale when the revision moves, which is how an edit shows up.
  static final Map<String, String> _cache = <String, String>{};
  static int _cacheRevision = 0;

  String? _svg;
  int _loadedRevision = -1;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _load();
  }

  Future<void> _load() async {
    if (widget.userId.isEmpty) return;
    final revision = ref.read(avatarRevisionProvider);
    if (revision != _cacheRevision) {
      _cache.clear();
      _cacheRevision = revision;
    }

    final cached = _cache[widget.userId];
    if (cached != null) {
      setState(() {
        _svg = cached;
        _loadedRevision = revision;
      });
      return;
    }

    if (_loading) return;
    _loading = true;
    try {
      final svg = await ref.read(apiClientProvider).avatarSvg(widget.userId);
      if (!mounted) return;
      if (svg.isNotEmpty) _cache[widget.userId] = svg;
      setState(() {
        _svg = svg.isEmpty ? null : svg;
        _loadedRevision = revision;
      });
    } catch (_) {
      // Offline, or not in a party with them any more. Initials it is.
      if (mounted) {
        setState(() {
          _svg = null;
          _loadedRevision = revision;
        });
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(avatarRevisionProvider, (previous, next) {
      if (next != _loadedRevision) _load();
    });

    final svg = _svg;
    if (svg == null) {
      return _Initials(name: widget.name, size: widget.size);
    }
    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: SvgPicture.string(
          svg,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          semanticsLabel: widget.name,
          placeholderBuilder: (_) => _Initials(
            name: widget.name,
            size: widget.size,
          ),
        ),
      ),
    );
  }
}

/// What every one of these surfaces showed before there were avatars, and what
/// they show again when one can't be drawn.
class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: wp.surface2, shape: BoxShape.circle),
      child: Text(
        initialsOf(name),
        style: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w700,
          color: wp.text,
        ),
      ),
    );
  }
}

String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = words.map((w) => w[0]).join().toUpperCase();
  if (letters.isEmpty) return '?';
  return letters.length > 2 ? letters.substring(0, 2) : letters;
}
