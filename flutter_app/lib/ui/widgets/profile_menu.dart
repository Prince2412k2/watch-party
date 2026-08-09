import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../state/state.dart';
import '../../state/theme_provider.dart';
import '../../update/desktop_updater.dart';
import '../analog_tokens.dart';
import '../palette.dart';
import '../theme_mode.dart';
import '../tokens.dart';
import 'app_dialog.dart';
import 'avatar_view.dart';
import 'icon_tray.dart';

/// The top-right profile control: an avatar that expands an [IconTray] of
/// actions leftwards out from beside itself.
///
/// This replaced a 250px dropdown card that listed the same actions as labelled
/// rows plus two lines of status text. The card was the heaviest object on a
/// stage whose whole premise is that the artwork is the interface — it covered
/// a sixth of the poster to offer four things, three of which are used once a
/// month.
///
/// What the card's text lines carried now lives in tooltips: the account name
/// on the avatar, the installed version on the update button. Nothing was
/// dropped, it just stopped being on screen when nobody asked for it.
///
/// A tap anywhere outside the control closes the tray without swallowing that
/// tap from the content beneath, via [TapRegion].
class ProfileMenu extends ConsumerStatefulWidget {
  const ProfileMenu({super.key});

  @override
  ConsumerState<ProfileMenu> createState() => _ProfileMenuState();
}

class _ProfileMenuState extends ConsumerState<ProfileMenu>
    with TickerProviderStateMixin {
  /// Built in [initState], not as a `late final` initializer, and vsynced by
  /// the plural mixin — see the note on the popcorn control's controller: a
  /// lazy field plus [SingleTickerProviderStateMixin] asserts after a hot
  /// reload, because the field resets and the handed-out ticker does not.
  late final AnimationController _tray;

  bool get _open => _tray.value > 0;

  @override
  void initState() {
    super.initState();
    _tray = AnimationController(
      vsync: this,
      duration: AnalogMotion.drawerMs,
      reverseDuration: AnalogMotion.exitMs,
    );
    // This control is the app's one persistent view of "me", so it is where the
    // profile gets fetched. Deferred past the first frame because loading it
    // moves provider state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(profileProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tray.dispose();
    super.dispose();
  }

  void _close() {
    if (_open) _tray.reverse();
  }

  Future<void> _signOut() async {
    _close();
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
    final accountName = ref.watch(
      authProvider.select((s) => s.user?.name ?? 'Profile'),
    );
    final userId = ref.watch(authProvider.select((s) => s.user?.userId));
    // What you call yourself wins over the account you signed in with.
    final displayName = ref.watch(profileProvider.select((s) => s.shownName));
    final name = displayName.isNotEmpty ? displayName : accountName;

    final update = ref.watch(desktopUpdateProvider);
    final mode = ref.watch(themeModeProvider);

    return TapRegion(
      onTapOutside: (_) => _close(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTray(
            animation: _tray,
            // Left-to-right; the last one is nearest the avatar, which is where
            // the cursor already is when the tray opens.
            children: [
              TrayButton(
                icon: _updateIcon(update.status),
                tooltip: _updateTooltip(update),
                badge:
                    update.status == UpdateStatus.available ||
                    update.status == UpdateStatus.readyToInstall,
                busy:
                    update.status == UpdateStatus.checking ||
                    update.status == UpdateStatus.downloading ||
                    update.status == UpdateStatus.loading,
                // A download knows how far along it is, so it says so in place
                // of the glyph rather than making you hover for the tooltip.
                progress: update.status == UpdateStatus.downloading
                    ? update.progress
                    : null,
                onTap: _updateAction(ref, update),
              ),
              TrayButton(
                icon: switch (mode) {
                  AppThemeMode.light => Icons.light_mode_outlined,
                  AppThemeMode.balanced => Icons.contrast,
                  AppThemeMode.dark => Icons.dark_mode_outlined,
                },
                tooltip: 'Appearance: ${_modeLabel(mode)}',
                onTap: () =>
                    ref.read(themeModeProvider.notifier).set(_next(mode)),
              ),
              TrayButton(
                icon: Icons.tune,
                tooltip: 'Edit profile',
                onTap: () {
                  _close();
                  context.push(Routes.profile);
                },
              ),
              TrayButton(
                icon: Icons.logout,
                tooltip: 'Sign out',
                tint: kSemanticRed,
                onTap: _signOut,
              ),
            ],
          ),
          _Avatar(
            userId: userId,
            name: name,
            animation: _tray,
            onTap: () => _open ? _tray.reverse() : _tray.forward(),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.userId,
    required this.name,
    required this.animation,
    required this.onTap,
  });

  final String? userId;
  final String name;
  final Animation<double> animation;
  final VoidCallback onTap;

  /// The handle. Sized to sit level with the tray it opens — matching
  /// [IconTray.thickness] is what makes the two read as one object rather than
  /// a circle parked next to a pill.
  static const double _face = IconTray.thickness;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: name,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final t = animation.value.clamp(0.0, 1.0);
              return Container(
                // A ring that thickens as the tray comes out. It is what ties
                // the circle to the pill: the avatar is the handle the tray
                // hangs off, not a separate control sitting next to it.
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: wp.stage,
                  border: Border.all(color: wp.line2, width: 3 * t),
                ),
                padding: EdgeInsets.all(3 * t),
                child: child,
              );
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: _face,
                  height: _face,
                  child: userId == null
                      ? Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: wp.text,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            initialsOf(name),
                            style: TextStyle(
                              fontFamily: AppFonts.sans,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: wp.bg,
                            ),
                          ),
                        )
                      : AvatarView(userId: userId!, name: name, size: _face),
                ),
                Positioned(
                  top: 0,
                  right: -3,
                  child: Container(
                    width: 15,
                    height: 15,
                    decoration: BoxDecoration(
                      color: kBrandRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: wp.stage, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _updateIcon(UpdateStatus status) => switch (status) {
  UpdateStatus.available => Icons.system_update_alt,
  // Downloaded and waiting on you. A restart glyph, because that is what
  // pressing it does — the download already happened.
  UpdateStatus.readyToInstall => Icons.restart_alt,
  UpdateStatus.error => Icons.error_outline,
  _ => Icons.refresh,
};

/// The version line the dropdown used to print, now only shown when asked for.
/// It is still the first thing anyone needs when reporting a bug, so it leads.
String _updateTooltip(UpdateState state) {
  final version = 'Version ${state.installedVersion}';
  final action = switch (state.status) {
    UpdateStatus.available => 'Update to ${state.release!.version}',
    UpdateStatus.downloading =>
      'Downloading ${(state.progress * 100).round()}%',
    // Says what it costs. Installing quits and relaunches the app, and the one
    // moment that matters is when someone is mid-film.
    UpdateStatus.readyToInstall =>
      'Install ${state.release?.version ?? 'update'} and restart',
    UpdateStatus.checking || UpdateStatus.loading => 'Checking...',
    _ => 'Check for updates',
  };
  final message = state.message;
  return message == null ? '$version\n$action' : '$version\n$action\n$message';
}

VoidCallback? _updateAction(WidgetRef ref, UpdateState state) =>
    switch (state.status) {
      // `available` is a transient state now — check() starts the download
      // itself — but if it is ever reached, pressing fetches rather than
      // installs. Only readyToInstall applies an update, because only a
      // deliberate press should quit the app.
      UpdateStatus.available =>
        () => ref.read(desktopUpdateProvider.notifier).download(),
      UpdateStatus.readyToInstall =>
        () => ref.read(desktopUpdateProvider.notifier).install(),
      UpdateStatus.checking ||
      UpdateStatus.downloading ||
      UpdateStatus.loading => null,
      _ => () => ref.read(desktopUpdateProvider.notifier).check(),
    };

String _modeLabel(AppThemeMode mode) => switch (mode) {
  AppThemeMode.light => 'Light',
  AppThemeMode.balanced => 'Balanced',
  AppThemeMode.dark => 'Dark',
};

/// One button cycles all three, in the order the old segmented control listed
/// them. Three states is the most a cycle can carry before you stop being able
/// to predict where the next tap lands.
AppThemeMode _next(AppThemeMode mode) => switch (mode) {
  AppThemeMode.light => AppThemeMode.balanced,
  AppThemeMode.balanced => AppThemeMode.dark,
  AppThemeMode.dark => AppThemeMode.light,
};
