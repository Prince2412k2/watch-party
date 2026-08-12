import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key holding whether artwork wears its paper texture.
const kArtworkTexturePrefKey = 'ui.artworkTexture';

/// Whether posters and the stage backdrop are printed on crumpled stock.
///
/// Persisted, because it is a taste decision rather than a session one: someone
/// who turns the paper off does not want to turn it off again every launch.
///
/// It reads itself at construction instead of being injected at boot like
/// [ServerConfigNotifier]. The server URL has to be known before the first
/// frame — the router sends you to setup without one — but this only decides
/// how artwork looks, so a frame or two of texture before the stored `false`
/// arrives costs nothing and keeps the boot path free of another await.
class ArtworkTextureNotifier extends StateNotifier<bool> {
  ArtworkTextureNotifier({bool initial = true}) : super(initial) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    // `mounted` first, and on its own: reading `state` is itself an assertion
    // that this is still alive, so testing `stored != state` before the guard
    // throws rather than skipping — and this await outlives short-lived
    // containers routinely, a hot restart being the obvious one.
    if (!mounted) return;
    final stored = prefs.getBool(kArtworkTexturePrefKey);
    if (stored != null && stored != state) state = stored;
  }

  Future<void> set(bool value) async {
    if (value == state) return;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kArtworkTexturePrefKey, value);
  }

  Future<void> toggle() => set(!state);
}

final artworkTextureProvider =
    StateNotifierProvider<ArtworkTextureNotifier, bool>(
      (ref) => ArtworkTextureNotifier(),
    );
