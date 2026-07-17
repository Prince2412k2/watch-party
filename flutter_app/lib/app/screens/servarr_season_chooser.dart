import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';

/// Season chooser (series only) — pick and download individual seasons. Mirrors
/// `FindDownload.tsx`'s `SeasonChooser`: a season request is monitor-only (adds
/// the show to Sonarr on first use, flips the chosen season(s) to monitored, and
/// fires a SeasonSearch), POSTing `/sonarr/request-season` with the exact
/// `{series, seasons[], qualityProfileId, languageProfileId, rootFolderPath}`
/// body. A not-yet-added lookup echoes TVDB's default `monitored:true`, which
/// must NOT read as already-monitored unless the series [isAdded].
class ServarrSeasonChooser extends ConsumerStatefulWidget {
  const ServarrSeasonChooser({
    super.key,
    required this.item,
    required this.onWholeSeriesFallback,
  });

  final ServarrTitle item;
  final VoidCallback onWholeSeriesFallback;

  @override
  ConsumerState<ServarrSeasonChooser> createState() =>
      _ServarrSeasonChooserState();
}

class _Season {
  _Season(Map<String, dynamic> raw)
      : seasonNumber = (raw['seasonNumber'] as num?)?.toInt() ?? 0,
        monitored = raw['monitored'] == true,
        totalEpisodeCount = (raw['totalEpisodeCount'] as num?)?.toInt();
  final int seasonNumber;
  final bool monitored;
  final int? totalEpisodeCount;
}

class _ServarrSeasonChooserState extends ConsumerState<ServarrSeasonChooser> {
  // Per-season session state: seasonNumber → 'requesting' | 'requested' | 'error'.
  final Map<int, String> _req = {};

  bool get _added => widget.item.isAdded;

  List<_Season> get _real => (widget.item.seasons.map(_Season.new).toList()
        ..removeWhere((s) => s.seasonNumber < 1))
      ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));

  List<_Season> get _specials =>
      widget.item.seasons.map(_Season.new).where((s) => s.seasonNumber == 0).toList();

  String _stateOf(_Season s) =>
      _req[s.seasonNumber] ?? (_added && s.monitored ? 'monitored' : 'idle');

  bool get _anyRequesting => _req.values.any((v) => v == 'requesting');

  Future<void> _request(List<int> nums) async {
    if (nums.isEmpty) return;
    setState(() {
      for (final n in nums) {
        _req[n] = 'requesting';
      }
    });
    try {
      final meta = await ref.read(servarrMetaProvider(ServarrKind.series).future);
      if (meta == null) throw Exception('meta');
      await ref.read(apiClientProvider).servarrPost('sonarr/request-season', body: {
        'series': widget.item.raw,
        'seasons': nums,
        'qualityProfileId': meta.qualityProfileId,
        'languageProfileId': meta.languageProfileId,
        'rootFolderPath': meta.rootFolderPath,
      });
      if (!mounted) return;
      setState(() {
        for (final n in nums) {
          _req[n] = 'requested';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        for (final n in nums) {
          _req[n] = 'error';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final real = _real;
    final specials = _specials;
    final meta = ref.watch(servarrMetaProvider(ServarrKind.series));

    // No season list at all → whole-series fallback so the button is never a
    // dead end.
    if (real.isEmpty && specials.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl),
        child: AppButton(
          label: 'Download series',
          icon: Icons.download,
          variant: AppButtonVariant.primary,
          onPressed: widget.onWholeSeriesFallback,
        ),
      );
    }

    return meta.when(
      loading: () => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.md),
            Text('Loading seasons…', style: AppTheme.dim),
          ],
        ),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.lg),
        child: ServarrNoticeBox(
          text: 'Download options are unavailable right now.',
        ),
      ),
      data: (m) {
        if (m == null) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.lg),
            child: ServarrNoticeBox(
              text: 'Download options are unavailable right now.',
            ),
          );
        }
        final allReal = real.map((s) => s.seasonNumber).toList();
        final allMonitored = real.isNotEmpty &&
            real.every((s) =>
                _stateOf(s) == 'monitored' || _stateOf(s) == 'requested');

        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'Choose seasons',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: wp.text,
                      ),
                    ),
                    const Spacer(),
                    if (real.length > 1)
                      AppButton(
                        label: 'All seasons',
                        icon: allMonitored ? Icons.check : Icons.download,
                        variant: allMonitored
                            ? AppButtonVariant.secondary
                            : AppButtonVariant.primary,
                        onPressed: _anyRequesting || allMonitored
                            ? null
                            : () => _request(allReal),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                for (final s in real) ...[
                  _SeasonRow(
                    label: 'Season ${s.seasonNumber}',
                    count: _count(s),
                    state: _stateOf(s),
                    disabled: _anyRequesting,
                    onRequest: () => _request([s.seasonNumber]),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (specials.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'SPECIALS',
                    style: AppTheme.mono.copyWith(
                      fontSize: 11.5,
                      color: wp.faint,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final s in specials) ...[
                    _SeasonRow(
                      label: 'Specials',
                      count: _count(s) ?? 'Extras & one-offs',
                      state: _stateOf(s),
                      disabled: _anyRequesting,
                      specials: true,
                      onRequest: () => _request([s.seasonNumber]),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
                const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: wp.faint),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'A requested season is monitored and searched — episodes '
                        'download on their own as they\'re found.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: wp.faint,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _count(_Season s) {
    final c = s.totalEpisodeCount;
    if (c == null || c <= 0) return null;
    return '$c episode${c == 1 ? '' : 's'}';
  }
}

class _SeasonRow extends StatelessWidget {
  const _SeasonRow({
    required this.label,
    required this.count,
    required this.state,
    required this.disabled,
    required this.onRequest,
    this.specials = false,
  });
  final String label;
  final String? count;
  final String state;
  final bool disabled;
  final bool specials;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Opacity(
      opacity: specials ? 0.82 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: wp.surface2.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: wp.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: wp.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    count ?? '—',
                    style: AppTheme.mono.copyWith(fontSize: 12, color: wp.faint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _right(context),
          ],
        ),
      ),
    );
  }

  Widget _right(BuildContext context) {
    switch (state) {
      case 'requesting':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 7),
            Text('Requesting…', style: AppTheme.dim),
          ],
        );
      case 'requested':
        return const AppChip(label: 'Searching…', icon: Icons.auto_awesome);
      case 'monitored':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppChip(label: 'Monitoring', icon: Icons.check),
            const SizedBox(width: AppSpacing.sm),
            AppButton(
              label: 'Search',
              icon: Icons.search,
              variant: AppButtonVariant.secondary,
              onPressed: disabled ? null : onRequest,
            ),
          ],
        );
      case 'error':
        return AppButton(
          label: 'Retry',
          icon: Icons.error_outline,
          variant: AppButtonVariant.danger,
          onPressed: disabled ? null : onRequest,
        );
      default:
        return AppButton(
          label: 'Download',
          icon: Icons.download,
          variant: AppButtonVariant.primary,
          onPressed: disabled ? null : onRequest,
        );
    }
  }
}

/// A small standalone notice box (season chooser errors) — theme-scoped.
class ServarrNoticeBox extends StatelessWidget {
  const ServarrNoticeBox({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.red),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: wp.text, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
