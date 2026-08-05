import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../state/auth_provider.dart';
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

/// Process-wide store of fetched avatar drawings.
///
/// Shared across every avatar on screen: a party redraws constantly and these
/// are tens of kilobytes each, so refetching per rebuild would be wasteful.
///
/// Every entry is scoped to the identity it was fetched under — the server it
/// came from and the account that asked for it. Account ids are only unique
/// within a server, so a plain `userId` key served one server's drawing of
/// "user 7" to a different server's user 7; and the server decides what a given
/// viewer is allowed to see (you get a face for someone you share a party
/// with), so a drawing fetched as one account is not answerable to the next
/// account to sign in on this machine.
class _AvatarCache {
  static final Map<String, String> _entries = <String, String>{};
  static String _scope = '';
  static int _revision = -1;

  /// `NUL` cannot appear in a URL or a Jellyfin id, so no combination of scope
  /// parts can be spelled by a different combination.
  static String keyFor(String scope, String userId) => '$scope\u0000$userId';

  /// Drops everything the moment the identity or the revision moves: an edited
  /// avatar, a different server, or a different account all mean every drawing
  /// held here describes something that is no longer on screen.
  static void _reset(String scope, int revision) {
    if (scope == _scope && revision == _revision) return;
    _entries.clear();
    _scope = scope;
    _revision = revision;
  }

  static String? read(String scope, int revision, String userId) {
    _reset(scope, revision);
    return _entries[keyFor(scope, userId)];
  }

  static void write(String scope, int revision, String userId, String svg) {
    _reset(scope, revision);
    _entries[keyFor(scope, userId)] = svg;
  }
}

class _AvatarViewState extends ConsumerState<AvatarView> {
  String? _svg;
  int _loadedRevision = -1;

  /// Bumped for every load. A fetch that finishes after a newer one started —
  /// or after the widget was recycled onto a different person, which the old
  /// in-flight flag turned into "never load the new one at all" — is dropped
  /// instead of drawn.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _svg = null;
      _load();
    }
  }

  /// Which server and which viewer this drawing belongs to.
  String get _scope {
    final server = ref.read(apiClientProvider).baseUrl;
    final viewer = ref.read(authProvider).user?.userId ?? '';
    return '$server\u0000$viewer';
  }

  Future<void> _load() async {
    if (widget.userId.isEmpty) return;
    final generation = ++_generation;
    final scope = _scope;
    final revision = ref.read(avatarRevisionProvider);

    final cached = _AvatarCache.read(scope, revision, widget.userId);
    if (cached != null) {
      setState(() {
        _svg = cached;
        _loadedRevision = revision;
      });
      return;
    }

    try {
      final svg = await ref.read(apiClientProvider).avatarSvg(widget.userId);
      if (!mounted || generation != _generation) return;
      // Re-read rather than trust the captured values: an edit or a sign-out
      // during the fetch means this drawing answers a question nobody is
      // asking any more, and caching it under the current identity would serve
      // it to whoever is there now.
      if (_scope != scope || ref.read(avatarRevisionProvider) != revision) {
        return;
      }
      if (svg.isNotEmpty) {
        _AvatarCache.write(scope, revision, widget.userId, svg);
      }
      setState(() {
        _svg = svg.isEmpty ? null : svg;
        _loadedRevision = revision;
      });
    } catch (_) {
      // Offline, or not in a party with them any more. Initials it is.
      if (!mounted || generation != _generation) return;
      setState(() {
        _svg = null;
        _loadedRevision = revision;
      });
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
