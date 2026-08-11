import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analog/chrome/analog_button.dart';
import '../../analog/chrome/analog_dialog.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';

/// Login. Jellyfin username/password against the real [DioApiClient].
///
/// Two panes on a grey gradient: the reel turning on the left, the form on the
/// right. No card — the fields sit directly on the stage. The card was a panel
/// floating on an empty screen, which is a lot of frame around four controls.
///
/// Below [_twoPaneWidth] the reel is dropped rather than stacked. It is
/// atmosphere, and a narrow window should spend its height on the form.
///
/// Backend-agnostic: a small gear in the top-right corner opens a dialog to
/// set the backend URL. It's persisted (via [serverConfigProvider]) and stays
/// in effect until logout. This is a desktop-only affordance the web has no
/// equivalent for; it is kept, not removed to match web.
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
    // The dialog owns its controller and returns the TEXT, rather than the
    // caller owning a controller and reading it back after the await.
    //
    // That older shape crashed: showAnalogDialog resolves the instant pop() is
    // called, but the route is still animating out and its TextField keeps
    // rebuilding for the length of that transition. Disposing the controller
    // on the line after the await meant the next frame rebuilt a TextField
    // around a dead one — "A TextEditingController was used after being
    // disposed", thrown from deep inside the framework's own animation update
    // with nothing in the trace pointing back here.
    final url = await showAnalogDialog<String>(
      context: context,
      builder: (_) => _ServerUrlDialog(initial: current),
    );
    if (url != null && url.trim().isNotEmpty) {
      await ref.read(serverConfigProvider.notifier).setUrl(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final server = ref.watch(serverConfigProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: _stage),
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final form = _LoginForm(
                  user: _user,
                  pass: _pass,
                  loading: auth.loading,
                  error: auth.error,
                  onSubmit: _submit,
                );
                if (constraints.maxWidth < _twoPaneWidth) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 48,
                      ),
                      child: SizedBox(width: _formWidth, child: form),
                    ),
                  );
                }
                return Row(
                  children: [
                    // The reel gets the larger share and is centred in it, so
                    // it reads as the room rather than as an illustration
                    // pinned beside a form.
                    Expanded(
                      flex: 6,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(48),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 480,
                              maxHeight: 480,
                            ),
                            child: const AspectRatio(
                              aspectRatio: 1,
                              child: ReelAnimation(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 48,
                          ),
                          child: SizedBox(width: _formWidth, child: form),
                        ),
                      ),
                    ),
                  ],
                );
              },
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
      ),
    );
  }
}

/// Below this the reel is dropped and the form centres on its own.
const double _twoPaneWidth = 880;
const double _formWidth = 340;

/// The grey the whole screen sits on. Flat colour looked like a missing
/// texture behind something as saturated as the reel; this is barely a
/// gradient, just enough to give the stage a top and a bottom.
const LinearGradient _stage = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF2B2C30), Color(0xFF161719)],
);

/// Everything you type, with no frame around it.
class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.user,
    required this.pass,
    required this.loading,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController user;
  final TextEditingController pass;
  final bool loading;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Welcome back',
          style: TextStyle(
            color: wp.text,
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in with your Jellyfin account',
          style: TextStyle(
            color: wp.dim,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 36),
        _Field(
          caption: 'Username',
          child: AppTextField(
            controller: user,
            autofocus: true,
            enabled: !loading,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _Field(
          caption: 'Password',
          child: AppTextField(
            controller: pass,
            obscureText: true,
            enabled: !loading,
            onSubmitted: (_) => onSubmit(),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          // Animate the error in each time it appears/changes.
          Reveal(
            key: ValueKey(error),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: const Color(0x1FE0655E),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0x59E0655E)),
              ),
              child: Text(
                error!,
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
          label: loading ? 'Signing in…' : 'Sign in',
          variant: AppButtonVariant.primary,
          expand: true,
          busy: loading,
          onPressed: loading ? null : onSubmit,
        ),
      ],
    );
  }
}

String _hostOf(String? url) {
  if (url == null || url.isEmpty) return '';
  return Uri.tryParse(url)?.host ?? url;
}

/// A form field: the web's uppercase-mono caption (JetBrains Mono, 11.5px,
/// .14em tracking, weight 700, `--faint`) over the input. Rendered here rather
/// than via [AppTextField]'s own label so it matches Login.tsx:50,58 without
/// changing the shared widget's sentence-case label contract.
class _Field extends StatelessWidget {
  const _Field({required this.caption, required this.child});
  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caption.toUpperCase(),
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.6, // .14em × 11.5px
            color: wp.faint,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
      ],
    );
  }
}

/// Top-right server control: a gear plus the current host (if set), so the user
/// always knows which backend they're signing in to and can change it. Reads
/// theme tokens so it stays legible in Light as well as Dark.
class _ServerConfigButton extends StatelessWidget {
  const _ServerConfigButton({required this.host, required this.onTap});
  final String host;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnalogButton(
      label: host.isEmpty ? 'Set server' : host,
      icon: Icons.dns_outlined,
      tone: AnalogButtonTone.ghost,
      dense: true,
      onPressed: onTap,
    );
  }
}

/// The server-URL prompt, owning its own text controller.
///
/// Stateful purely so the controller's lifetime is tied to the ROUTE rather
/// than to the caller's `await`. A dialog outlives its own `pop()` by the
/// length of the exit transition, and anything the caller disposes in that
/// window is still being rebuilt.
class _ServerUrlDialog extends StatefulWidget {
  const _ServerUrlDialog({required this.initial});

  final String initial;

  @override
  State<_ServerUrlDialog> createState() => _ServerUrlDialogState();
}

class _ServerUrlDialogState extends State<_ServerUrlDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Server URL',
      body: 'Where your Watchparty backend lives. https:// is assumed.',
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          // Null rather than the current text: the caller distinguishes
          // "cancelled" from "saved an empty box" on this alone.
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Save',
          variant: AppButtonVariant.primary,
          onPressed: _save,
        ),
      ],
      child: AppTextField(
        controller: _controller,
        hint: 'e.g. dsk-4161.tail0a3558.ts.net',
        autofocus: true,
        onSubmitted: (_) => _save(),
      ),
    );
  }
}
