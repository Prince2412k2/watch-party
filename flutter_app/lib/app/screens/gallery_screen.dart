import 'package:flutter/material.dart';

import '../../ui/ui.dart';

/// Dev-only showcase (PLAN §4 E1/T1.2): every core widget + the color/type
/// scale, rendered on one scrollable page so a human (or a golden test) can
/// eyeball the whole design system at once. Not linked from the nav shell —
/// reach it at `/gallery`.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  final _textController = TextEditingController();
  bool _busy = false;
  String? _selectedChip = 'Action';

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          children: [
            const Text('Design system gallery', style: AppTheme.displaySmall),
            const SizedBox(height: AppSpacing.sm),
            const Text('Every core widget + the cinematic-minimal token set, in one place.',
                style: AppTheme.dim),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Color'),
            _ColorSwatches(),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Type scale'),
            _TypeScale(),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Buttons'),
            _ButtonsShowcase(busy: _busy, onToggleBusy: () => setState(() => _busy = !_busy)),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Chips'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final g in const ['Action', 'Drama', 'Comedy', 'Sci-Fi'])
                  AppChip(
                    label: g,
                    selected: _selectedChip == g,
                    onTap: () => setState(() => _selectedChip = g),
                  ),
                const AppChip(label: 'LIVE', tone: AppChipTone.live),
                const AppChip(label: 'Failed', tone: AppChipTone.danger, icon: Icons.error_outline),
                const AppChip(label: 'Downloaded', tone: AppChipTone.success, icon: Icons.check),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Text field'),
            SizedBox(
              width: 360,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(controller: _textController, label: 'Username', hint: 'root'),
                  const SizedBox(height: AppSpacing.lg),
                  const AppTextField(label: 'Password', obscureText: true, hint: '••••••••'),
                  const SizedBox(height: AppSpacing.lg),
                  const AppTextField(label: 'Disabled', enabled: false, hint: 'Not editable'),
                  const SizedBox(height: AppSpacing.lg),
                  const AppTextField(label: 'With error', errorText: 'Invalid credentials'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Poster cards'),
            SizedBox(
              height: 300,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  PosterCard(title: 'Arrival', subtitle: '2016', progress: 0.4, onTap: () {}),
                  const SizedBox(width: AppSpacing.lg),
                  PosterCard(title: 'The Matrix', subtitle: '1999', onTap: () {}),
                  const SizedBox(width: AppSpacing.lg),
                  const PosterCard(title: 'Untitled', subtitle: null),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Loading skeletons'),
            const Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                LoadingSkeleton(width: 120, height: 16),
                LoadingSkeleton(width: 200, height: 16),
                LoadingSkeleton(width: 160, height: 220, borderRadius: AppSpacing.radius),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Nav rail'),
            SizedBox(
              height: 300,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ColoredBox(
                    color: AppColors.surface,
                    child: NavRail(
                      destinations: const [
                        NavDestination(icon: Icons.home_outlined, label: 'Home', route: '/home'),
                        NavDestination(icon: Icons.explore_outlined, label: 'Browse', route: '/browse'),
                        NavDestination(icon: Icons.download_outlined, label: 'Downloads', route: '/downloads', badge: 2),
                      ],
                      currentRoute: '/home',
                      onSelect: (_) {},
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xl),
                  ColoredBox(
                    color: AppColors.surface,
                    child: NavRail(
                      compact: true,
                      destinations: const [
                        NavDestination(icon: Icons.home_outlined, label: 'Home', route: '/home'),
                        NavDestination(icon: Icons.explore_outlined, label: 'Browse', route: '/browse'),
                        NavDestination(icon: Icons.download_outlined, label: 'Downloads', route: '/downloads', badge: 2),
                      ],
                      currentRoute: '/browse',
                      onSelect: (_) {},
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Dialogs & scrim'),
            Row(
              children: [
                AppButton(
                  label: 'Show dialog',
                  onPressed: () => AppDialog.show(
                    context,
                    title: 'Leave party?',
                    body: 'Playback will stop for everyone if you are the host.',
                    actions: [
                      AppButton(label: 'Cancel', variant: AppButtonVariant.ghost, onPressed: () => Navigator.of(context).pop()),
                      AppButton(label: 'Leave', variant: AppButtonVariant.danger, onPressed: () => Navigator.of(context).pop()),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                AppButton(
                  label: 'Confirm helper',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => showConfirm(context, title: 'Delete download?', danger: true),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            const SectionHeader(title: 'Empty & error states'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  height: 320,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppSpacing.radius)),
                    child: const EmptyState(
                      title: 'No downloads yet',
                      message: 'Titles you download for offline playback show up here.',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                SizedBox(
                  width: 320,
                  height: 320,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppSpacing.radius)),
                    child: ErrorState(
                      title: 'Couldn\'t load library',
                      message: 'Check your connection and try again.',
                      onRetry: () {},
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatches extends StatelessWidget {
  const _ColorSwatches();

  static const _swatches = [
    ('bg', AppColors.bg),
    ('surface', AppColors.surface),
    ('surface2', AppColors.surface2),
    ('surface3', AppColors.surface3),
    ('text', AppColors.text),
    ('dim', AppColors.dim),
    ('faint', AppColors.faint),
    ('accent', AppColors.accent),
    ('green (success)', AppColors.green),
    ('red (danger/live)', AppColors.red),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.lg,
      children: [
        for (final (name, color) in _swatches)
          SizedBox(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: AppColors.line),
                  ),
                ),
                const SizedBox(height: 6),
                Text(name, style: const TextStyle(color: AppColors.dim, fontSize: 11.5)),
              ],
            ),
          ),
      ],
    );
  }
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Display small', style: AppTheme.displaySmall),
        SizedBox(height: AppSpacing.sm),
        Text('Title large', style: AppTheme.titleLarge),
        SizedBox(height: AppSpacing.sm),
        Text('Title medium', style: AppTheme.titleMedium),
        SizedBox(height: AppSpacing.sm),
        Text('Body text at 14.5px medium weight', style: AppTheme.body),
        SizedBox(height: AppSpacing.sm),
        Text('Dim secondary text', style: AppTheme.dim),
        SizedBox(height: AppSpacing.sm),
        Text('CAPTION / LABEL', style: AppTheme.caption),
        SizedBox(height: AppSpacing.sm),
        Text('MONO 00:12:34', style: AppTheme.mono),
      ],
    );
  }
}

class _ButtonsShowcase extends StatelessWidget {
  const _ButtonsShowcase({required this.busy, required this.onToggleBusy});
  final bool busy;
  final VoidCallback onToggleBusy;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppButton(label: 'Play', variant: AppButtonVariant.primary, icon: Icons.play_arrow, onPressed: () {}),
        AppButton(label: 'Secondary', onPressed: () {}),
        AppButton(label: 'Ghost', variant: AppButtonVariant.ghost, onPressed: () {}),
        AppButton(label: 'Delete', variant: AppButtonVariant.danger, icon: Icons.delete_outline, onPressed: () {}),
        AppButton(label: 'Disabled', onPressed: null),
        AppButton(label: busy ? 'Working…' : 'Toggle busy', busy: busy, onPressed: onToggleBusy),
      ],
    );
  }
}
