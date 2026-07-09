import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/state.dart';
import '../../ui/ui.dart';

/// Simple placeholder screens (PLAN §3.7). Each owning epic replaces its screen;
/// Phase 0 gives every route a real, navigable widget.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.title, this.body});
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          if (body != null) Text(body!, style: AppTheme.dim),
        ],
      ),
    );
  }
}

/// Login (E2 owns). Phase 0 renders the form and calls the (mock) authProvider.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController(text: 'root');
  final _pass = TextEditingController(text: 'root');

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    ref.listen(authProvider, (_, next) {
      if (next.isAuthenticated) context.go('/home');
    });

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Watchparty', style: AppTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.xl),
              AppTextField(controller: _user, label: 'Username'),
              const SizedBox(height: AppSpacing.lg),
              AppTextField(controller: _pass, label: 'Password', obscureText: true),
              if (auth.error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(auth.error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Sign in',
                variant: AppButtonVariant.primary,
                expand: true,
                busy: auth.loading,
                onPressed: () => ref
                    .read(authProvider.notifier)
                    .login(_user.text, _pass.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BrowseScreen extends StatelessWidget {
  const BrowseScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _Placeholder(title: 'Browse', body: 'Search + grid + filters (E3).');
}

class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.itemId});
  final String itemId;
  @override
  Widget build(BuildContext context) =>
      _Placeholder(title: 'Title detail', body: 'Item $itemId — metadata, Play, Download (E3/E4).');
}

class PartyScreen extends StatelessWidget {
  const PartyScreen({super.key, this.partyId});
  final String? partyId;
  @override
  Widget build(BuildContext context) => _Placeholder(
      title: 'Watch Party',
      body: partyId == null ? 'Create or join a party (E5/E6/E7).' : 'Party $partyId');
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _Placeholder(title: 'Downloads', body: 'Resumable downloads + progress (E8).');
}

class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _Placeholder(title: 'Offline', body: 'Downloaded titles, play with no network (E8).');
}

class ServarrScreen extends StatelessWidget {
  const ServarrScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const _Placeholder(title: 'Find & Download', body: 'Servarr search / releases / queue (E9).');
}
