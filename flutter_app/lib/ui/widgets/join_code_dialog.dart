import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../palette.dart';
import '../tokens.dart';
import 'app_button.dart';

/// The join-by-code dialog (mirrors the web `JoinDialog`, `WebShell.tsx`). Takes
/// an 8-character hex party code, validates it against `^[0-9A-F]{8}$`, then runs
/// [onJoin] (which emits `party:join`). Errors surface inline; on success the
/// dialog pops with the server status (`'joined'` | `'waiting'`) so the caller
/// can route accordingly.
class JoinCodeDialog extends StatefulWidget {
  const JoinCodeDialog({super.key, required this.onJoin});

  /// Joins the party for [code] and resolves to the server status. Throws a
  /// message string / [Object] on failure, shown inline.
  final Future<String> Function(String code) onJoin;

  @override
  State<JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<JoinCodeDialog> {
  static final _codePattern = RegExp(r'^[0-9A-F]{8}$');

  final _controller = TextEditingController();
  bool _joining = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_joining) return;
    final code = _controller.text.trim().toUpperCase();
    if (!_codePattern.hasMatch(code)) {
      setState(() => _error = 'Enter the 8-character party code');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final status = await widget.onJoin(code);
      if (mounted) Navigator.of(context).pop(status);
    } catch (e) {
      if (mounted) {
        setState(() {
          _joining = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Dialog(
      backgroundColor: wp.surface,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        side: BorderSide(color: wp.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ROOM CODE',
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: wp.faint,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Join a party',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: wp.text,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Party code',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: wp.dim,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 8,
                enabled: !_joining,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  UpperCaseHexFormatter(),
                  LengthLimitingTextInputFormatter(8),
                ],
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submit(),
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 18,
                  letterSpacing: 3,
                  color: wp.text,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'A1B2C3D4',
                  hintStyle: TextStyle(
                    fontFamily: AppFonts.mono,
                    fontSize: 18,
                    letterSpacing: 3,
                    color: wp.faint,
                  ),
                  filled: true,
                  fillColor: wp.surface2,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    borderSide: BorderSide(color: wp.line2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    borderSide: BorderSide(color: wp.text),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    borderSide: BorderSide(color: wp.line),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize: 12.5,
                    color: kSemanticRed,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: _joining ? 'Joining…' : 'Join party',
                variant: AppButtonVariant.primary,
                expand: true,
                busy: _joining,
                onPressed: _joining ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Restricts input to uppercase hex characters (`0-9A-F`) as the user types —
/// the party-code alphabet.
class UpperCaseHexFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final filtered = newValue.text
        .toUpperCase()
        .replaceAll(RegExp('[^0-9A-F]'), '');
    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
    );
  }
}
