/// The analog chrome kit.
///
/// Buttons, plates, inputs, badges, switches, menus, toasts and the command
/// palette — everything the app frames its content *with*, as opposed to the
/// browse kit in `analog/widgets/` and the player kit in `analog/player/`,
/// which are the content.
///
/// It sits on the same generated tokens (`ui/analog_tokens.dart`) as those two
/// and reads neither `ui/tokens.dart` nor `ui/palette.dart`, for the reason
/// given in `analog/analog.dart`: this is the replacement for them, not a
/// retheme of them.
///
/// Two rules hold across every widget in here, and each has a test:
///
/// * **Nothing is hover-only.** Every control takes focus, activates on
///   Enter/Space/Select, and carries an accessible name — the reference's
///   cross-input contract covers remotes and touch, not just mice.
/// * **No state is signalled by colour alone.** Focus draws a ring, selection
///   draws a detent, a press sinks the plate, disabled flattens it, danger
///   doubles the frame.
///
/// Where Material already owns plumbing worth keeping — text editing, menu
/// routes, tooltip placement, modal routes — these widgets wrap it rather than
/// reimplement it, and replace only the paint.
library;

export 'analog_badge.dart';
export 'analog_button.dart';
export 'analog_command_palette.dart';
export 'analog_dialog.dart';
export 'analog_menu.dart';
export 'analog_panel.dart';
export 'analog_pressable.dart';
export 'analog_side_strip.dart';
export 'analog_progress.dart';
export 'analog_switch.dart';
export 'analog_text_field.dart';
export 'analog_toast.dart';
export 'analog_tooltip.dart';
export 'liquid_glass.dart';
