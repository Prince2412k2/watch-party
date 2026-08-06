/// The analog primitive kit (issue #66).
///
/// The browse widgets and one focus store, plus the chrome kit in `chrome/`
/// that replaced shadcn_flutter — all sitting directly on the generated tokens
/// in `ui/analog_tokens.dart` and the shared interaction cores in
/// `analog/browse_core.dart`. Nothing here reads `ui/tokens.dart` or
/// `ui/palette.dart`: this is the replacement for those, not a retheme of them
/// (see `app/shared/design/README.md`).
library;

export 'browse_core.dart';
export 'chrome/chrome.dart';
export 'focus_memory.dart';
export 'widgets/analog_nav.dart';
export 'widgets/analog_poster.dart';
export 'widgets/analog_shelf.dart';
export 'widgets/analog_stage.dart';
export 'widgets/analog_toolbox.dart';
