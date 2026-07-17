import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/servarr_provider.dart';
import '../../ui/ui.dart';

/// Download-options dialog (mirrors `FindDownload.tsx`'s `OptionsDialog`): pick a
/// quality profile + root folder (and, for series, a language profile plus
/// monitor / search-now toggles) before running the server-authoritative
/// request. Resolves with the request outcome via [onAdded] on definitive
/// success.
Future<void> showServarrOptionsDialog(
  BuildContext context, {
  required ServarrTitle item,
  required ServarrKind kind,
  required void Function(String? outcome) onAdded,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.66),
    builder: (_) =>
        _ServarrOptionsDialog(item: item, kind: kind, onAdded: onAdded),
  );
}

class _ServarrOptionsDialog extends ConsumerStatefulWidget {
  const _ServarrOptionsDialog({
    required this.item,
    required this.kind,
    required this.onAdded,
  });

  final ServarrTitle item;
  final ServarrKind kind;
  final void Function(String? outcome) onAdded;

  @override
  ConsumerState<_ServarrOptionsDialog> createState() =>
      _ServarrOptionsDialogState();
}

class _ServarrOptionsDialogState extends ConsumerState<_ServarrOptionsDialog> {
  int? _qualityProfileId;
  String? _rootFolderPath;
  int? _languageProfileId;
  bool _monitor = true;
  bool _searchNow = true;

  bool _submitting = false;
  String? _error;
  String? _warn;
  String? _okOutcome;
  bool _initialized = false;

  bool get _isSeries => widget.kind == ServarrKind.series;

  @override
  Widget build(BuildContext context) {
    final profilesAsync = ref.watch(servarrProfilesProvider(widget.kind));

    return _DialogShell(
      maxWidth: 520,
      child: profilesAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, _) => _ErrorBody(
          message: 'Download options are unavailable right now.',
          onClose: () => Navigator.of(context).pop(),
        ),
        data: (meta) {
          if (!_initialized) {
            _qualityProfileId = meta.profiles.isNotEmpty
                ? meta.profiles.first['id'] as int?
                : null;
            _rootFolderPath = meta.rootFolders.isNotEmpty
                ? meta.rootFolders.first['path'] as String?
                : null;
            _languageProfileId = meta.langProfiles.isNotEmpty
                ? meta.langProfiles.first['id'] as int?
                : null;
            _initialized = true;
          }
          final canSubmit = !_submitting &&
              _qualityProfileId != null &&
              _rootFolderPath != null &&
              _okOutcome == null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DialogHeader(
                eyebrow: _isSeries ? 'SERIES' : 'MOVIE',
                title: widget.item.title,
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: AppSpacing.lg),
              _FieldLabel('Quality'),
              _DropdownInt(
                value: _qualityProfileId,
                items: [
                  for (final p in meta.profiles)
                    (p['id'] as int, (p['name'] ?? '').toString()),
                ],
                onChanged: (v) => setState(() => _qualityProfileId = v),
              ),
              const SizedBox(height: AppSpacing.md),
              _FieldLabel('Save to'),
              _DropdownString(
                value: _rootFolderPath,
                items: [
                  for (final f in meta.rootFolders)
                    (
                      (f['path'] ?? '').toString(),
                      _folderLabel(f),
                    ),
                ],
                onChanged: (v) => setState(() => _rootFolderPath = v),
              ),
              if (_isSeries && meta.langProfiles.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                _FieldLabel('Language'),
                _DropdownInt(
                  value: _languageProfileId,
                  items: [
                    for (final p in meta.langProfiles)
                      (p['id'] as int, (p['name'] ?? '').toString()),
                  ],
                  onChanged: (v) => setState(() => _languageProfileId = v),
                ),
              ],
              if (_isSeries) ...[
                const SizedBox(height: AppSpacing.md),
                _ToggleRow(
                  label: 'Keep monitoring',
                  hint: 'Monitor all episodes',
                  value: _monitor,
                  onChanged: (v) => setState(() => _monitor = v),
                ),
                const SizedBox(height: AppSpacing.sm),
                _ToggleRow(
                  label: 'Search now',
                  hint: 'Start looking for a release immediately',
                  value: _searchNow,
                  onChanged: (v) => setState(() => _searchNow = v),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                _Notice(icon: Icons.error_outline, tone: _NoticeTone.error, text: _error!),
              ],
              if (_warn != null) ...[
                const SizedBox(height: AppSpacing.md),
                _Notice(icon: Icons.error_outline, tone: _NoticeTone.warn, text: _warn!),
              ],
              if (_okOutcome != null) ...[
                const SizedBox(height: AppSpacing.md),
                _Notice(
                  icon: Icons.check,
                  tone: _NoticeTone.ok,
                  text: _okOutcome == 'grabbed'
                      ? 'Downloading — added to your library'
                      : _okOutcome == 'monitoring'
                          ? 'Added — monitoring for releases'
                          : 'Already in your library',
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: _submitting
                    ? (_isSeries ? 'Adding…' : 'Finding a release…')
                    : _okOutcome != null
                        ? 'Done'
                        : _warn != null
                            ? 'Try again'
                            : 'Download',
                icon: _okOutcome != null ? Icons.check : Icons.download,
                busy: _submitting,
                expand: true,
                variant: _okOutcome != null
                    ? AppButtonVariant.secondary
                    : AppButtonVariant.primary,
                onPressed: canSubmit ? _submit : null,
              ),
            ],
          );
        },
      ),
    );
  }

  String _folderLabel(Map<String, dynamic> f) {
    final path = (f['path'] ?? '').toString();
    final free = f['freeSpace'];
    if (free is num && free > 0) {
      return '$path  (${(free / 1e9).round()} GB free)';
    }
    return path;
  }

  Future<void> _submit() async {
    if (_submitting || _qualityProfileId == null || _rootFolderPath == null) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
      _warn = null;
    });
    final body = widget.kind == ServarrKind.movie
        ? {
            'movie': widget.item.raw,
            'qualityProfileId': _qualityProfileId,
            'rootFolderPath': _rootFolderPath,
          }
        : {
            'series': widget.item.raw,
            'qualityProfileId': _qualityProfileId,
            'languageProfileId': _languageProfileId,
            'rootFolderPath': _rootFolderPath,
            'monitor': _monitor,
            'searchNow': _searchNow,
          };
    try {
      final api = ref.read(apiClientProvider);
      final res =
          await api.servarrPost('${widget.kind.service}/request', body: body);
      final outcome = (res as Map)['outcome'] as String?;
      if (!mounted) return;
      if (outcome == 'grabbed' ||
          outcome == 'monitoring' ||
          outcome == 'exists') {
        setState(() {
          _okOutcome = outcome;
          _submitting = false;
        });
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.of(context).pop();
        widget.onAdded(outcome);
      } else if (outcome == 'no_release') {
        setState(() {
          _warn = 'No release available right now — try again later.';
          _submitting = false;
        });
      } else {
        setState(() {
          _error = 'Couldn\'t check for a release right now. Please try again.';
          _submitting = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Couldn\'t start the request. Please try again.';
        _submitting = false;
      });
    }
  }
}

/// Shared modal surface for the acquire dialogs — a themed rounded card on the
/// barrier, scroll-safe, max-width constrained.
class _DialogShell extends StatelessWidget {
  const _DialogShell({required this.child, this.maxWidth = 560});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 640),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: wp.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(color: wp.line),
                boxShadow: wp.cardShadow,
              ),
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.eyebrow,
    required this.title,
    required this.onClose,
    this.poster,
  });
  final String eyebrow;
  final String title;
  final VoidCallback onClose;
  final Widget? poster;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (poster != null) ...[poster!, const SizedBox(width: AppSpacing.md)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                eyebrow,
                style: AppTheme.mono.copyWith(
                  fontSize: 11.5,
                  color: wp.faint,
                  letterSpacing: 0.7,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.titleLarge.copyWith(color: wp.text),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(
          onPressed: onClose,
          iconSize: 18,
          icon: Icon(Icons.close, color: wp.dim),
          tooltip: 'Close',
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Notice(icon: Icons.error_outline, tone: _NoticeTone.error, text: message),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Close',
          expand: true,
          variant: AppButtonVariant.secondary,
          onPressed: onClose,
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.wp.dim,
          ),
        ),
      );
}

class _DropdownInt extends StatelessWidget {
  const _DropdownInt({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final int? value;
  final List<(int, String)> items;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return _DropdownFrame(
      child: DropdownButton<int>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: wp.surface2,
        style: TextStyle(color: wp.text, fontSize: 14),
        icon: Icon(Icons.expand_more, color: wp.dim),
        items: [
          for (final (id, name) in items)
            DropdownMenuItem(value: id, child: Text(name)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _DropdownString extends StatelessWidget {
  const _DropdownString({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final String? value;
  final List<(String, String)> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return _DropdownFrame(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        dropdownColor: wp.surface2,
        style: TextStyle(color: wp.text, fontSize: 14),
        icon: Icon(Icons.expand_more, color: wp.dim),
        items: [
          for (final (v, label) in items)
            DropdownMenuItem(
              value: v,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _DropdownFrame extends StatelessWidget {
  const _DropdownFrame({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: wp.surface2,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: wp.line2),
      ),
      child: child,
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    this.hint,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String? hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: wp.surface2.withValues(alpha: 0.5),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: wp.text,
                    ),
                  ),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hint!,
                        style: TextStyle(fontSize: 12, color: wp.faint),
                      ),
                    ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: wp.onAccent,
              activeTrackColor: wp.text,
            ),
          ],
        ),
      ),
    );
  }
}

enum _NoticeTone { error, warn, ok }

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.tone, required this.text});
  final IconData icon;
  final _NoticeTone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final color = switch (tone) {
      _NoticeTone.error => AppColors.red,
      _NoticeTone.warn => AppColors.red,
      _NoticeTone.ok => AppColors.green,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
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

// Shared acquire-dialog primitives reused by the release picker + manual source.
class ServarrDialogShell extends StatelessWidget {
  const ServarrDialogShell({super.key, required this.child, this.maxWidth = 640});
  final Widget child;
  final double maxWidth;
  @override
  Widget build(BuildContext context) =>
      _DialogShell(maxWidth: maxWidth, child: child);
}

class ServarrDialogHeader extends StatelessWidget {
  const ServarrDialogHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.onClose,
    this.poster,
  });
  final String eyebrow;
  final String title;
  final VoidCallback onClose;
  final Widget? poster;
  @override
  Widget build(BuildContext context) => _DialogHeader(
        eyebrow: eyebrow,
        title: title,
        onClose: onClose,
        poster: poster,
      );
}

class ServarrNotice extends StatelessWidget {
  const ServarrNotice({
    super.key,
    required this.icon,
    required this.text,
    this.error = true,
  });
  final IconData icon;
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => _Notice(
        icon: icon,
        tone: error ? _NoticeTone.error : _NoticeTone.ok,
        text: text,
      );
}
