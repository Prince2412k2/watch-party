import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/state.dart';
import '../../ui/ui.dart';

/// Login (E2 owns). Jellyfin username/password against the real
/// [DioApiClient]; matches the web app's minimal card layout
/// (`app/client/src/pages/Login.jsx`): "Welcome back" / "Sign in with your
/// Jellyfin account".
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _submit() {
    if (_user.text.trim().isEmpty) return;
    ref.read(authProvider.notifier).login(_user.text.trim(), _pass.text);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 380,
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 48),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Watchparty',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 44),
                const Text(
                  'Welcome back',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in with your Jellyfin account',
                  style: TextStyle(
                    color: AppColors.dim,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 28),
                AppTextField(
                  controller: _user,
                  label: 'Username',
                  autofocus: true,
                  enabled: !auth.loading,
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  controller: _pass,
                  label: 'Password',
                  obscureText: true,
                  enabled: !auth.loading,
                  onSubmitted: (_) => _submit(),
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0x1FE0655E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0x59E0655E)),
                    ),
                    child: Text(
                      auth.error!,
                      style: const TextStyle(color: AppColors.red, fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: auth.loading ? 'Signing in…' : 'Sign in',
                  variant: AppButtonVariant.primary,
                  expand: true,
                  busy: auth.loading,
                  onPressed: auth.loading ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
