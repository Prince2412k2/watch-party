import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../analog/chrome/analog_toast.dart';
import '../../data/api_client.dart';
import '../../state/offline_provider.dart';
import '../../state/state.dart';
import '../../ui/ui.dart';
import '../router.dart';
import 'profile_screen.dart' show profileAvatarHeroTag, profileHeaderHeight;

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
          SafeArea(
            // The editor's geometry, to the pixel: same header room, same
            // padding, same 4/6 split, same alignment, same size formula. The
            // pencil leads there, so the face must not jump when you follow
            // it. Structured the same way too — the alignment resolves
            // against the box it is given, so matching only the numbers and
            // not the nesting still lands somewhere else.
            child: Column(
              children: [
                const SizedBox(height: profileHeaderHeight),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final face = (constraints.maxWidth * 0.25).clamp(
                        300.0,
                        420.0,
                      );
                      return Padding(
                        // The header's room, held open. Settings has no header of
                        // its own, but the editor does, and without this the face
                        // would sit a header's height higher than the one it flies
                        // into.
                        padding: const EdgeInsets.fromLTRB(44, 12, 52, 36),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: _Identity(
                                userId: auth.user?.userId,
                                face: face,
                                name: _name.text.isEmpty
                                    ? (auth.user?.name ?? 'Profile')
                                    : _name.text,
                                controller: _name,
                                busy: _savingName,
                                onSave: _saveName,
                                onEditAvatar: () =>
                                    context.push(Routes.profile),
                              ),
                            ),
                            const SizedBox(width: 48),
                            Expanded(
                              flex: 6,
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
                      );
                    },
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
    required this.face,
    required this.name,
    required this.controller,
    required this.busy,
    required this.onSave,
    required this.onEditAvatar,
  });

  final String? userId;
  final double face;
  final String name;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback onEditAvatar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The editor puts the face at Alignment(0, -0.18) of this same box.
        // Resolved by hand rather than with an Align so the name can sit
        // under it WITHOUT moving it: inside a Column the name's height would
        // push the face up by half of it, and the whole point is that the two
        // pages agree on where the face is.
        // Align resolves as (box - child) * (1 + a) / 2. Writing it as
        // box * (1 + a) / 2 - child / 2 is a different number — they differ
        // by child * (1 - (1 + a) / 2), which for this face is 31.5px, and
        // that is exactly how far the two pages disagreed by.
        const a = -0.18;
        final top = (constraints.maxHeight - face) * (1 + a) / 2;
        final left = (constraints.maxWidth - face) / 2;

        return Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: face,
              height: face,
              child: _Face(
                userId: userId,
                name: name,
                face: face,
                onEdit: onEditAvatar,
              ),
            ),
            Positioned(
              left: left,
              top: top + face + AppSpacing.xl,
              width: face,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Caption('Name'),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(
                    controller: controller,
                    enabled: !busy,
                    onSubmitted: (_) => onSave(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: busy ? 'Saving…' : 'Save name',
                    variant: AppButtonVariant.primary,
                    busy: busy,
                    onPressed: busy ? null : onSave,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The face, with the pencil that leads to the editor sitting on it.
class _Face extends StatelessWidget {
  const _Face({
    required this.userId,
    required this.name,
    required this.face,
    required this.onEdit,
  });

  final String? userId;
  final String name;
  final double face;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Stack(
      children: [
        // Tagged so the face flies to the editor rather than cutting to it —
        // the same shared element the posters use.
        Positioned.fill(
          child: Hero(
            tag: profileAvatarHeroTag,
            child: userId == null
                ? const SizedBox.shrink()
                : ClipOval(
                    child: AvatarView(userId: userId!, name: name, size: face),
                  ),
          ),
        ),
        // On the face, not beside it: the thing it edits is the thing it is
        // attached to, so there is no label to write.
        Positioned(
          right: face * 0.04,
          bottom: face * 0.04,
          child: Tooltip(
            message: 'Edit avatar',
            child: Material(
              color: wp.surface2,
              shape: CircleBorder(side: BorderSide(color: wp.line2)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(Icons.edit, size: 20, color: wp.text),
                ),
              ),
            ),
          ),
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
