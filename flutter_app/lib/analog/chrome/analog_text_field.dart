import 'package:flutter/material.dart';

import '../../ui/analog_tokens.dart';

/// A single-line input on the analog surface ramp.
///
/// The editing itself is Material's [EditableText] by way of [TextField] — IME
/// composition, selection handles, autofill, the platform context menu and the
/// accessibility bridge are precisely the plumbing that should not be rebuilt.
/// Everything visible is this file's: a warm plate, a hairline that thickens
/// from [AnalogHairline.idlePx] to [AnalogHairline.activePx] on focus, and no
/// rounded pill.
///
/// The focus mark is a *thicker* frame rather than a brighter one, so the
/// caret's location is legible with the colour removed.
class AnalogTextField extends StatefulWidget {
  const AnalogTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.obscureText = false,
    this.errorText,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.leading,
    this.trailing,
    this.textInputAction,
    this.textStyle,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final bool obscureText;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final Widget? leading;
  final Widget? trailing;
  final TextInputAction? textInputAction;
  final TextStyle? textStyle;

  @override
  State<AnalogTextField> createState() => _AnalogTextFieldState();
}

class _AnalogTextFieldState extends State<AnalogTextField> {
  FocusNode? _owned;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_owned ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(AnalogTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      (oldWidget.focusNode ?? _owned)?.removeListener(_onFocus);
      _node.addListener(_onFocus);
      _onFocus();
    }
  }

  @override
  void dispose() {
    (widget.focusNode ?? _owned)?.removeListener(_onFocus);
    _owned?.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!mounted) return;
    final has = _node.hasFocus;
    if (has != _focused) setState(() => _focused = has);
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;
    final enabled = widget.enabled;

    final Color frame;
    final double frameWidth;
    if (hasError) {
      frame = AnalogColor.statusDanger;
      frameWidth = AnalogHairline.idlePx;
    } else if (!enabled) {
      frame = AnalogColor.line;
      frameWidth = AnalogPoster.framePx;
    } else if (_focused) {
      frame = AnalogColor.ink;
      frameWidth = AnalogHairline.idlePx;
    } else {
      frame = AnalogColor.lineStrong;
      frameWidth = AnalogPoster.framePx;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: const TextStyle(
              fontFamily: AnalogType.sansFamily,
              color: AnalogColor.inkDim,
              fontSize: 12,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AnalogSpace.smPx),
        ],
        AnimatedContainer(
          duration: AnalogMotion.chromeFadeMs,
          curve: AnalogMotion.chromeFadeEase,
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: AnalogSpace.mdPx),
          decoration: BoxDecoration(
            color: enabled
                ? AnalogColor.stageSurface
                : AnalogColor.stageGround,
            borderRadius: BorderRadius.circular(AnalogRadius.chromePx),
            border: Border.all(color: frame, width: frameWidth),
          ),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: AnalogSpace.smPx),
              ],
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _node,
                  obscureText: widget.obscureText,
                  autofocus: widget.autofocus,
                  enabled: enabled,
                  onSubmitted: widget.onSubmitted,
                  onChanged: widget.onChanged,
                  textInputAction: widget.textInputAction,
                  cursorColor: AnalogColor.ink,
                  cursorWidth: AnalogPoster.framePx * 2,
                  cursorRadius: Radius.zero,
                  style:
                      widget.textStyle ??
                      TextStyle(
                        fontFamily: AnalogType.sansFamily,
                        fontSize: 14,
                        color: enabled
                            ? AnalogColor.ink
                            : AnalogColor.inkFaint,
                      ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: AnalogSpace.smPx + 2,
                    ),
                    hintText: widget.hint,
                    hintStyle: const TextStyle(
                      fontFamily: AnalogType.sansFamily,
                      fontSize: 14,
                      color: AnalogColor.inkFaint,
                    ),
                  ),
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: AnalogSpace.smPx),
                widget.trailing!,
              ],
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: AnalogSpace.smPx),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A mark as well as a colour: the message is still marked as an
              // error when the red is not perceivable.
              const Padding(
                padding: EdgeInsets.only(top: 1, right: AnalogSpace.xsPx + 2),
                child: Icon(
                  Icons.error_outline,
                  size: 13,
                  color: AnalogColor.statusDanger,
                ),
              ),
              Flexible(
                child: Text(
                  widget.errorText!,
                  style: const TextStyle(
                    fontFamily: AnalogType.sansFamily,
                    color: AnalogColor.statusDanger,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
