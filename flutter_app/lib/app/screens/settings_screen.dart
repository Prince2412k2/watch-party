import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../analog/chrome/analog_toast.dart';
import '../../data/api_client.dart';
import '../../state/offline_provider.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';
import '../router.dart';
import 'title_layout.dart';

/// Settings.
///
/// The account menu's tune button used to open the avatar editor directly,
/// which is one of the things you might want from it rather than the thing.
/// This is the page it opens now; the editor is a step further in, behind the
/// pencil on the face.
///
/// Laid out as the stages are — a column of content on the left, a column
/// beside it — so arriving here from any of them lands on the same geometry.
///
///   ┌────────────────────────────────────────────────┐
///   │   ( face ) ✎          Server                   │
///   │                       Username                 │
///   │   Name  [        ]    Password                 │
///   │                       Storage                  │
///   └────────────────────────────────────────────────┘
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _current = TextEditingController();
  final _next = TextEditingController();

  bool _savingName = false;
  bool _savingUrl = false;
  bool _savingPassword = false;
  bool _clearing = false;

  /// Filled once, from whatever the providers held when this opened. Not kept
  /// in sync afterwards: a field that rewrites itself under the cursor while
  /// you are typing in it is worse than one that is briefly stale.
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(profileProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _current.dispose();
    _next.dispose();
    super.dispose();
  }

  void _say(String message, {AnalogToastTone tone = AnalogToastTone.success}) {
    if (mounted) showAnalogToast(context, message, tone: tone);
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty || _savingName) return;
    setState(() => _savingName = true);
    final error = await ref
        .read(profileProvider.notifier)
        .save(displayName: name);
    if (!mounted) return;
    setState(() => _savingName = false);
    _say(
      error ?? 'Saved',
      tone: error == null ? AnalogToastTone.success : AnalogToastTone.danger,
    );
  }

  Future<void> _saveUrl() async {
    final url = _url.text.trim();
    if (url.isEmpty || _savingUrl) return;
    setState(() => _savingUrl = true);
    await ref.read(serverConfigProvider.notifier).setUrl(url);
    if (!mounted) return;
    setState(() => _savingUrl = false);
    _say('Server updated');
  }

  Future<void> _savePassword() async {
    if (_savingPassword) return;
    final current = _current.text;
    final next = _next.text;
    if (current.isEmpty || next.isEmpty) {
      _say('Both passwords are needed', tone: AnalogToastTone.warning);
      return;
    }
    setState(() => _savingPassword = true);
    try {
      await ref.read(apiClientProvider).changePassword(current, next);
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _say('Password changed');
    } catch (e) {
      if (!mounted) return;
      _say(
        e is ApiException ? e.message : 'Could not change password',
        tone: AnalogToastTone.danger,
      );
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _clearCache() async {
    if (_clearing) return;
    final ok = await showConfirm(
      context,
      title: 'Clear cached video?',
      body:
          'Everything streamed so far is removed to free the space. Titles '
          'you downloaded stay where they are, and anything cleared streams '
          'again next time you watch it.',
      confirmLabel: 'Clear',
      danger: true,
    );
    if (!ok || !mounted) return;

    setState(() => _clearing = true);
    // Downloads are the one thing this must not touch: they were asked for
    // explicitly, and on a connection worth downloading over, re-fetching one
    // is not a recoverable mistake.
    final keep = {for (final r in ref.read(offlineProvider)) r.itemId};
    try {
      final removed = await ref
          .read(mediaCacheProxyProvider)
          .clear(protected: keep);
      if (!mounted) return;
      _say(
        removed == 0
            ? 'Nothing cached to clear'
            : 'Cleared $removed ${removed == 1 ? 'title' : 'titles'}',
      );
    } catch (_) {
      if (!mounted) return;
      _say('Could not clear the cache', tone: AnalogToastTone.danger);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final auth = ref.watch(authProvider);
    final profile = ref.watch(profileProvider);
    final server = ref.watch(serverConfigProvider);

    if (!_seeded) {
      _seeded = true;
      _name.text = profile.shownName.isNotEmpty
          ? profile.shownName
          : (auth.user?.name ?? '');
      _url.text = server ?? '';
    }

    return Scaffold(
      backgroundColor: wp.bg,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TitleLayout.padLeft,
              TitleLayout.padTop,
              TitleLayout.padLeft,
              48,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: TitleLayout.copyFlex,
                  child: _Identity(
                    userId: auth.user?.userId,
                    name: _name.text.isEmpty
                        ? (auth.user?.name ?? 'Profile')
                        : _name.text,
                    controller: _name,
                    busy: _savingName,
                    onSave: _saveName,
                    onEditAvatar: () => context.push(Routes.profile),
                  ),
                ),
                const SizedBox(width: TitleLayout.columnGap),
                Expanded(
                  flex: TitleLayout.asideFlex,
                  child: SingleChildScrollView(
                    child: _Connection(
                      url: _url,
                      current: _current,
                      next: _next,
                      username: auth.user?.name ?? '',
                      savingUrl: _savingUrl,
                      savingPassword: _savingPassword,
                      clearing: _clearing,
                      onSaveUrl: _saveUrl,
                      onSavePassword: _savePassword,
                      onClearCache: _clearCache,
                    ),
                  ),
                ),
              ],
            ),
          ),
          StageBackButton(
            onTap: () =>
                context.canPop() ? context.pop() : context.go(Routes.movies),
          ),
        ],
      ),
    );
  }
}

/// The face and what to call it.
class _Identity extends StatelessWidget {
  const _Identity({
    required this.userId,
    required this.name,
    required this.controller,
    required this.busy,
    required this.onSave,
    required this.onEditAvatar,
  });

  final String? userId;
  final String name;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onEditAvatar;

  static const double _face = 172;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The pencil sits ON the face rather than beside it: the thing it
        // edits is the thing it is attached to, and there is no label to write.
        SizedBox(
          width: _face,
          height: _face,
          child: Stack(
            children: [
              Positioned.fill(
                child: userId == null
                    ? const SizedBox.shrink()
                    : ClipOval(
                        child: AvatarView(
                          userId: userId!,
                          name: name,
                          size: _face,
                        ),
                      ),
              ),
              Positioned(
                right: 2,
                bottom: 2,
                child: Tooltip(
                  message: 'Edit avatar',
                  child: Material(
                    color: wp.surface2,
                    shape: CircleBorder(side: BorderSide(color: wp.line2)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onEditAvatar,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.edit, size: 18, color: wp.text),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Caption('Name'),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: 320,
          child: AppTextField(
            controller: controller,
            enabled: !busy,
            onSubmitted: (_) => onSave(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: busy ? 'Saving…' : 'Save name',
          variant: AppButtonVariant.primary,
          busy: busy,
          onPressed: busy ? null : onSave,
        ),
      ],
    );
  }
}

/// Where this app is pointed, who it is signed in as, and what it is holding
/// on disk.
class _Connection extends StatelessWidget {
  const _Connection({
    required this.url,
    required this.current,
    required this.next,
    required this.username,
    required this.savingUrl,
    required this.savingPassword,
    required this.clearing,
    required this.onSaveUrl,
    required this.onSavePassword,
    required this.onClearCache,
  });

  final TextEditingController url;
  final TextEditingController current;
  final TextEditingController next;
  final String username;
  final bool savingUrl;
  final bool savingPassword;
  final bool clearing;
  final VoidCallback onSaveUrl;
  final VoidCallback onSavePassword;
  final VoidCallback onClearCache;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Caption('Server'),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: url,
          enabled: !savingUrl,
          hint: 'e.g. watch.example.tech',
          onSubmitted: (_) => onSaveUrl(),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: savingUrl ? 'Saving…' : 'Save server',
          variant: AppButtonVariant.secondary,
          busy: savingUrl,
          onPressed: savingUrl ? null : onSaveUrl,
        ),

        const SizedBox(height: AppSpacing.xxl),
        _Caption('Username'),
        const SizedBox(height: AppSpacing.sm),
        // Shown, not editable. The account name belongs to the media server
        // and only an administrator there can change it; a box you can type
        // in that silently refuses to save is worse than a line of text.
        Text(
          username.isEmpty ? '—' : username,
          style: TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: wp.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Set on the media server.',
          style: TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 13,
            color: wp.faint,
          ),
        ),

        const SizedBox(height: AppSpacing.xxl),
        _Caption('Password'),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: current,
          obscureText: true,
          enabled: !savingPassword,
          hint: 'Current password',
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          controller: next,
          obscureText: true,
          enabled: !savingPassword,
          hint: 'New password',
          onSubmitted: (_) => onSavePassword(),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: savingPassword ? 'Changing…' : 'Change password',
          variant: AppButtonVariant.secondary,
          busy: savingPassword,
          onPressed: savingPassword ? null : onSavePassword,
        ),

        const SizedBox(height: AppSpacing.xxl),
        _Caption('Storage'),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Streaming keeps what it has already fetched so a rewatch does not '
          'pull it twice. Clearing frees that space; downloads are kept.',
          style: TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 13.5,
            height: 1.5,
            color: wp.dim,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: clearing ? 'Clearing…' : 'Clear cache',
          variant: AppButtonVariant.danger,
          busy: clearing,
          onPressed: clearing ? null : onClearCache,
        ),
      ],
    );
  }
}

/// The uppercase-mono run above each field, as the login screen sets it.
class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontFamily: AppFonts.mono,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.6,
      color: context.wp.faint,
    ),
  );
}
