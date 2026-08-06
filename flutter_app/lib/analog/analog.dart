/// The analog primitive kit (issue #66).
///
/// Five widgets and one focus store, all sitting directly on the generated
/// tokens in `ui/analog_tokens.dart` and the shared interaction cores in
/// `analog/browse_core.dart`. Nothing here reads `ui/tokens.dart` or
/// `ui/palette.dart`: this is the replacement for those, not a retheme of them
/// (see `app/shared/design/README.md`).
library;

export 'browse_core.dart';
export 'focus_memory.dart';
export 'widgets/analog_nav.dart';
export 'widgets/analog_poster.dart';
export 'widgets/analog_shelf.dart';
export 'widgets/analog_stage.dart';
export 'widgets/analog_toolbox.dart';
