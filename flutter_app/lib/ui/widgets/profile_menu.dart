import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/state.dart';
import '../../state/theme_provider.dart';
import '../../update/desktop_updater.dart';
import '../palette.dart';
import '../theme_mode.dart';
import '../tokens.dart';
import 'app_dialog.dart';

/// The top-right profile control (`.web-profile`, styles.css:313-331). A
/// circular avatar showing the signed-in user's initials with a red
/// notification dot; tapping it opens a dropdown with "Signed in as `name`", a
/// 3-way appearance switch bound to [themeModeProvider], and a red Sign out row.
///
/// A tap anywhere outside the control closes the menu (mirrors the web's
/// outside-`pointerdown` handler) without swallowing that tap from the content
/// beneath, via [TapRegion].
class ProfileMenu extends ConsumerStatefulWidget {
  const ProfileMenu({super.key});

  @override
  ConsumerState<ProfileMenu> createState() => _ProfileMenuState();
}

class _ProfileMenuState extends ConsumerState<ProfileMenu> {
  bool _open = false;

  Future<void> _signOut() async {
    setState(() => _open = false);
    final confirmed = await showConfirm(
      context,
      title: 'Sign out?',
      body: 'You will need to pick your server and sign in again.',
      confirmLabel: 'Sign out',
    );
    if (confirmed) await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(
      authProvider.select((s) => s.user?.name ?? 'Profile'),
    );

    return TapRegion(
      onTapOutside: (_) {
        if (_open) setState(() => _open = false);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _Avatar(
            initials: _initials(name),
            onTap: () => setState(() => _open = !_open),
          ),
          if (_open) ...[
            const SizedBox(height: 8),
            _Menu(name: name, onSignOut: _signOut),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials, required this.onTap});

  final String initials;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: wp.text, shape: BoxShape.circle),
              child: Text(
                initials,
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: wp.bg,
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: kBrandRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: wp.stage, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.name, required this.onSignOut});

  final String name;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    final update = ref.watch(desktopUpdateProvider);
    return Container(
      width: 250,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: wp.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: wp.line),
        boxShadow: [
          BoxShadow(
            color: wp.shadow,
            blurRadius: 50,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Signed in as',
                  style: TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize: 11,
                    color: wp.faint,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: wp.text,
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 0, 6, 6),
            child: _ThemeSwitch(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 3),
            child: Text(
              'Version ${update.installedVersion}',
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 11,
                color: wp.faint,
              ),
            ),
          ),
          _UpdateButton(
            state: update,
            onTap: update.status == UpdateStatus.available
                ? () => ref.read(desktopUpdateProvider.notifier).install()
                : update.status == UpdateStatus.checking ||
                      update.status == UpdateStatus.downloading ||
                      update.status == UpdateStatus.loading
                ? null
                : () => ref.read(desktopUpdateProvider.notifier).check(),
          ),
          if (update.message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: Text(
                update.message!,
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 10,
                  height: 1.25,
                  color: update.status == UpdateStatus.error
                      ? kSemanticRed
                      : wp.faint,
                ),
              ),
            ),
          _SignOutButton(onTap: onSignOut),
        ],
      ),
    );
  }
}

class _UpdateButton extends StatelessWidget {
  const _UpdateButton({required this.state, required this.onTap});

  final UpdateState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final downloading = state.status == UpdateStatus.downloading;
    final label = state.status == UpdateStatus.available
        ? 'Update to ${state.release!.version}'
        : downloading
        ? 'Downloading ${(state.progress * 100).round()}%'
        : state.status == UpdateStatus.checking
        ? 'Checking...'
        : 'Check for updates';
    return MouseRegion(
      cursor: onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt,
                size: 16,
                color: onTap == null ? wp.dim : wp.text,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppFonts.sans,
                    fontSize: 12,
                    color: onTap == null ? wp.dim : wp.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 3-way appearance segmented control (`.web-theme-switch`,
/// styles.css:284-312): sun → Light, blend → Balanced, moon → Dark. The active
/// button carries a surface-2 fill and full-strength text; the others are dim.
class _ThemeSwitch extends ConsumerWidget {
  const _ThemeSwitch();

  static const _options = [
    (AppThemeMode.light, Icons.light_mode_outlined, 'Light mode'),
    (AppThemeMode.balanced, Icons.contrast, 'Balanced mode'),
    (AppThemeMode.dark, Icons.dark_mode_outlined, 'Dark mode'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wp = context.wp;
    final mode = ref.watch(themeModeProvider);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: wp.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: wp.line),
      ),
      child: Row(
        children: [
          for (final (m, icon, label) in _options)
            Expanded(
              child: _ThemeButton(
                icon: icon,
                label: label,
                active: mode == m,
                onTap: () => ref.read(themeModeProvider.notifier).set(m),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeButton extends StatefulWidget {
  const _ThemeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ThemeButton> createState() => _ThemeButtonState();
}

class _ThemeButtonState extends State<_ThemeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final on = widget.active || _hover;
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: on ? wp.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(widget.icon, size: 16, color: on ? wp.text : wp.dim),
          ),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatefulWidget {
  const _SignOutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends State<_SignOutButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: _hover ? const Color(0x1AE0655E) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: const [
              Icon(Icons.logout, size: 16, color: kSemanticRed),
              SizedBox(width: 9),
              Text(
                'Sign out',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 13,
                  color: kSemanticRed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final letters = parts.map((w) => w[0]).join().toUpperCase();
  if (letters.isEmpty) return '?';
  return letters.length > 2 ? letters.substring(0, 2) : letters;
}
