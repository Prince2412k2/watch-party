import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;
import 'package:window_manager/window_manager.dart';

import '../state/state.dart';
import '../ui/command_palette.dart';
import '../ui/ui.dart';
import 'router.dart';
import 'screens/app_shell.dart';

/// Root widget. Wires the frozen theme + router. State DI lives at the
/// [ProviderScope]/[UncontrolledProviderScope] in `main.dart`; by the time this
/// widget builds, boot-time session restore has already resolved, so the
/// router's auth redirect (E2) never flashes the wrong screen.
///
/// The window is frameless + rounded (see `desktop_lifecycle.dart` +
/// `linux/runner/my_application.cc`): [VirtualWindowFrame] paints the rounded
/// corners, border, and shadow and provides edge-resize, while [_WindowBar]
/// draws the drag region + min/maximize/close controls the OS frame no longer
/// provides.
class WatchpartyApp extends ConsumerStatefulWidget {
  const WatchpartyApp({super.key, this.enableWindowFrame = true});

  /// The custom frameless window chrome (drag bar + rounded [VirtualWindowFrame])
  /// drives window_manager platform channels, which aren't available under
  /// `flutter test` — widget tests pass `false` to skip it.
  final bool enableWindowFrame;

  @override
  ConsumerState<WatchpartyApp> createState() => _WatchpartyAppState();
}

class _WatchpartyAppState extends ConsumerState<WatchpartyApp> {
  late final _router = buildRouter(ref);

  bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Watchparty',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        final Widget framed;
        if (!_isDesktop || !widget.enableWindowFrame) {
          framed = content;
        } else {
          // The title bar + content live ABOVE the router's Navigator, so they
          // have no Overlay ancestor of their own. Give them one here (a single
          // full-window Overlay entry) so the window-bar's shadcn tooltips —
          // whose PopoverOverlayHandler calls Overlay.of — resolve an Overlay
          // instead of asserting "No Overlay widget found". This also tightens
          // the previously unbounded _WindowBar Row cascade.
          framed = VirtualWindowFrame(
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => Column(
                    children: [
                      _WindowBar(router: _router),
                      Expanded(child: content),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        // ShadcnLayer wraps the ENTIRE frame (title bar + content) so shadcn
        // components everywhere — including the window-bar tooltips — resolve
        // their theme and overlay/tooltip infrastructure. PKG-E owns the
        // title-bar region below; this wrapper stays out of its way.
        return sc.ShadcnLayer(
          theme: AppShadcnTheme.dark,
          themeMode: sc.ThemeMode.dark,
          child: framed,
        );
      },
    );
  }
}

/// The unified, frameless title bar (PKG-E). One flat near-black strip that
/// consolidates what used to be two bars: the app-wide window controls (this
/// file's old `_WindowBar`) and the shell chrome — section title + Sign out —
/// that previously lived in `app_shell.dart`. Left→right it hosts a draggable
/// section-title region, a command-palette trigger, Sign out, and the
/// min/maximize/close controls. No gradient, no elevation — cinematic-minimal.
///
/// It sits ABOVE the router's Navigator, so its palette + sign-out actions
/// resolve a below-router context through [rootNavigatorKey]. The section title
/// tracks the live route via the router's `routeInformationProvider`. Sign out
/// + the palette trigger only appear once authenticated (nothing to search or
/// sign out of on the login screen); the drag region + window controls (with
/// their [sc.Tooltip]s) and double-tap-maximize are always on.
class _WindowBar extends ConsumerWidget {
  const _WindowBar({required this.router});

  final GoRouter router;

  static const double height = 44;

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> _openPalette(WidgetRef ref) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    await showCommandPalette(
      context: context,
      ref: ref,
      destinations: kShellDestinations,
      onNavigate: (route) => rootNavigatorKey.currentContext?.go(route),
    );
  }

  Future<void> _confirmLogout(WidgetRef ref) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    final ok = await showConfirm(
      context,
      title: 'Sign out?',
      body: 'You will need to pick your server and sign in again.',
      confirmLabel: 'Sign out',
    );
    if (ok) await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authProvider.select((s) => s.isAuthenticated));
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.line, width: 1)),
      ),
      child: Row(
        children: [
          // Draggable section-title strip. The title reacts to navigation via
          // the router's route-information provider; double-tap maximizes.
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: _toggleMaximize,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ListenableBuilder(
                      listenable: router.routeInformationProvider,
                      builder: (context, _) => Text(
                        shellSectionTitle(
                          router.routeInformationProvider.value.uri.path,
                        ),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dim,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (authed) ...[
            _ChromeButton(
              icon: Icons.search,
              label: 'Search',
              hint: Platform.isMacOS ? '⌘K' : 'Ctrl K',
              onPressed: () => _openPalette(ref),
            ),
            _ChromeButton(
              icon: Icons.logout,
              label: 'Sign out',
              onPressed: () => _confirmLogout(ref),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          _WindowButton(
            icon: Icons.remove,
            tooltip: 'Minimize',
            onPressed: windowManager.minimize,
          ),
          _WindowButton(
            icon: Icons.crop_square,
            tooltip: 'Maximize',
            iconSize: 13,
            onPressed: _toggleMaximize,
          ),
          _WindowButton(
            icon: Icons.close,
            tooltip: 'Close',
            hoverColor: AppColors.red,
            onPressed: windowManager.close,
          ),
        ],
      ),
    );
  }
}

/// A hover-lit chrome action (command-palette trigger, Sign out) styled for the
/// title bar: monochrome, flat, with an optional keyboard-hint pill.
class _ChromeButton extends StatefulWidget {
  const _ChromeButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.hint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final String? hint;

  @override
  State<_ChromeButton> createState() => _ChromeButtonState();
}

class _ChromeButtonState extends State<_ChromeButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = _hover ? AppColors.text : AppColors.dim;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: _hover ? AppColors.line : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: fg),
              const SizedBox(width: AppSpacing.sm),
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (widget.hint != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.line2),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    widget.hint!,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 10.5,
                      color: AppColors.faint,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.hoverColor,
    this.iconSize = 16,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? hoverColor;
  final double iconSize;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = _hover
        ? (widget.hoverColor ?? const Color(0x14FFFFFF))
        : Colors.transparent;
    final fg = (_hover && widget.hoverColor != null)
        ? Colors.white
        : (_hover ? AppColors.text : AppColors.dim);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      // shadcn's tooltip renders through ShadcnLayer's overlay handler, so it
      // works here in MaterialApp.router's builder (above the router's
      // Navigator) where a Material Tooltip has no Overlay ancestor.
      child: sc.Tooltip(
        waitDuration: const Duration(milliseconds: 600),
        tooltip: (context) => sc.TooltipContainer(child: Text(widget.tooltip)),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: _WindowBar.height,
            color: bg,
            child: Icon(widget.icon, size: widget.iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}
