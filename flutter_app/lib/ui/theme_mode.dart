/// The three persisted interface themes (matches the web `data-theme` values).
///
/// The web client persists the choice to `localStorage['watchparty-theme']`
/// (default `light`); the desktop client mirrors that via `shared_preferences`
/// in `state/theme_provider.dart`. [key] is the string written to storage — it
/// stays byte-identical to the web so a user's choice reads the same on either
/// client.
enum AppThemeMode {
  light('light'),
  balanced('balanced'),
  dark('dark');

  const AppThemeMode(this.key);

  /// The storage/`data-theme` value.
  final String key;

  /// Parse a stored [key] back to a mode, or null when unknown/absent.
  static AppThemeMode? fromKey(String? key) {
    for (final mode in values) {
      if (mode.key == key) return mode;
    }
    return null;
  }
}
