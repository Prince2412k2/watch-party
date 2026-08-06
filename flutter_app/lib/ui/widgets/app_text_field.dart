import 'package:flutter/widgets.dart';

import '../../analog/chrome/analog_text_field.dart';

/// FROZEN CONTRACT (PLAN §3.6). Now an [AnalogTextField]: the label/error
/// scaffolding the old wrapper built around the input moved *into* the
/// component, so the public signature is unchanged and every input in the app
/// gets the same frame, the same thickening focus hairline, and the same
/// marked error line.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.obscureText = false,
    this.errorText,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final bool obscureText;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AnalogTextField(
      controller: controller,
      label: label,
      hint: hint,
      obscureText: obscureText,
      errorText: errorText,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      autofocus: autofocus,
      enabled: enabled,
    );
  }
}
