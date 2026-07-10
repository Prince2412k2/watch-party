import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../../state/state.dart';
import '../../ui/ui.dart';

/// Login (E2 owns). Jellyfin username/password against the real
/// [DioApiClient]; matches the web app's minimal card layout
/// (`app/client/src/pages/Login.jsx`): "Welcome back" / "Sign in with your
/// Jellyfin account".
///
/// Backend-agnostic: a small gear in the top-right corner opens a dialog to
/// set the backend URL. It's persisted (via [serverConfigProvider]) and stays
/// in effect until logout.
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

  Future<void> _configureServer() async {
    final current = ref.read(serverConfigProvider) ?? '';
    final controller = TextEditingController(text: current);
    // Design-system dialog (acrylic shadcn surface) with AppButton actions,
    // replacing the raw Material AlertDialog + TextButtons. The builder context
    // (`ctx`) owns the dialog route, so popping it closes the dialog.
    final saved = await sc.showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Server URL',
        body: 'Where your Watchparty backend lives. https:// is assumed.',
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.ghost,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: 'Save',
            variant: AppButtonVariant.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
        child: AppTextField(
          controller: controller,
          hint: 'e.g. dsk-4161.tail0a3558.ts.net',
          autofocus: true,
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (saved == true && text.trim().isNotEmpty) {
      await ref.read(serverConfigProvider.notifier).setUrl(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final server = ref.watch(serverConfigProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              child: SizedBox(
                width: 380,
                child: sc.Card(
                  filled: true,
                  fillColor: AppColors.surface,
                  borderColor: AppColors.line,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 48,
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
                        // Animate the error in each time it appears/changes.
                        Reveal(
                          key: ValueKey(auth.error),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0x1FE0655E),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0x59E0655E),
                              ),
                            ),
                            child: Text(
                              auth.error!,
                              style: const TextStyle(
                                color: AppColors.red,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
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
          ),
          // Corner control to configure the backend URL.
          Positioned(
            top: 10,
            right: 10,
            child: _ServerConfigButton(
              host: _hostOf(server),
              onTap: _configureServer,
            ),
          ),
        ],
      ),
    );
  }
}

String _hostOf(String? url) {
  if (url == null || url.isEmpty) return '';
  return Uri.tryParse(url)?.host ?? url;
}

/// Top-right server control: a gear plus the current host (if set), so the user
/// always knows which backend they're signing in to and can change it. Ported
/// from a raw `TextButton.icon` to a shadcn ghost button (icon + host label).
class _ServerConfigButton extends StatelessWidget {
  const _ServerConfigButton({required this.host, required this.onTap});
  final String host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return sc.Button.ghost(
      onPressed: onTap,
      leading: const Icon(Icons.dns_outlined, size: 16, color: AppColors.faint),
      child: Text(
        host.isEmpty ? 'Set server' : host,
        style: const TextStyle(color: AppColors.faint, fontSize: 12),
      ),
    );
  }
}
