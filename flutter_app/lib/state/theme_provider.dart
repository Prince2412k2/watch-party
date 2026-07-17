import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme_mode.dart';

/// The persisted interface theme.
///
/// Sits ABOVE the shell chrome but BELOW the functional providers — switching
/// the mode rebuilds the theme/wash only and never remounts playback, party,
/// socket, LiveKit, chat, or download state (PLAN §global invariants).
///
/// Persistence mirrors the web client exactly: `shared_preferences` key
/// `watchparty-theme`, default [AppThemeMode.light]. The stored value is the
/// same string the web writes to `localStorage`, so the choice is consistent
/// across clients on the same machine convention.
class ThemeModeNotifier extends StateNotifier<AppThemeMode> {
  ThemeModeNotifier() : super(AppThemeMode.light) {
    _restore();
  }

  static const String storageKey = 'watchparty-theme';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = AppThemeMode.fromKey(prefs.getString(storageKey));
    if (stored != null && mounted) state = stored;
  }

  Future<void> set(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, mode.key);
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, AppThemeMode>(
  (ref) => ThemeModeNotifier(),
);
