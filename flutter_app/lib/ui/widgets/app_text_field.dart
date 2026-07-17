import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../palette.dart';
import '../tokens.dart';

/// FROZEN CONTRACT (PLAN §3.6). Rebuilt on `sc.TextField` (animated focus ring
/// comes for free); the label/error scaffolding around it is preserved so the
/// public signature and the cinematic layout are unchanged.
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
    final hasError = errorText != null;
    final wp = context.wp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: TextStyle(
              color: wp.dim,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        sc.TextField(
          controller: controller,
          obscureText: obscureText,
          autofocus: autofocus,
          enabled: enabled,
          onSubmitted: onSubmitted,
          onChanged: onChanged,
          placeholder: hint != null ? Text(hint!) : null,
          border: hasError ? Border.all(color: AppColors.red) : null,
        ),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            errorText!,
            style: const TextStyle(color: AppColors.red, fontSize: 12.5),
          ),
        ],
      ],
    );
  }
}
