import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../models/models.dart';
import '../../state/profile_provider.dart';
import '../../state/providers.dart';
import '../../ui/palette.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/avatar_view.dart';
import '../router.dart';

/// Profile editor — the native counterpart of the web's `/profile` page.
///
/// The pictures all come from the server: humation is a JavaScript renderer, so
/// this screen posts the configuration it currently has and displays what comes
/// back. The vocabulary of slots, parts and colours is read from
/// `/api/avatar/options` rather than hardcoded, so an asset-set update adds
/// options here without a change to this file.
///
/// Same shape as the web editor at a wide window: the preview stays put on the
/// left while the options scroll on the right.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const _nameMax = 32;
  static const _twoColumnWidth = 900.0;

  final TextEditingController _name = TextEditingController();

  AvatarOptions? _options;
  // Empty means "nothing overridden" — the avatar derived from the account.
  AvatarConfig _config = const AvatarConfig();
  String _accountName = '';

  String? _previewSvg;
  // slot id → part id → drawing.
  final Map<String, Map<String, String>> _thumbnails =
      <String, Map<String, String>>{};
  // The colours the current thumbnails were drawn in, so they are only redrawn
  // when the colours actually change rather than on every part tap.
  String _thumbnailColors = '';

  bool _loading = true;
  bool _saving = false;
  String? _status;
  bool _statusIsError = false;
  // Kept apart from [_status] (which reports saving): this is "the editor could
  // not be assembled", and it has to be visible on its own rather than inside
  // the options it is reporting the absence of.
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _colorKey(AvatarConfig config) {
    final keys = config.colors.keys.toList()..sort();
    return keys.map((k) => '$k=${config.colors[k]}').join(',');
  }

  static String _messageFor(Object error, String fallback) {
    if (error is ApiException) {
      // A 404 here means the server predates the avatar endpoints, which is
      // worth saying plainly rather than reporting as a generic failure.
      if (error.statusCode == 404) {
        return 'This server does not support avatars yet — it needs updating.';
      }
      return error.message;
    }
    return fallback;
  }

  /// The profile and the avatar vocabulary are fetched independently and
  /// reported separately. The name field only needs the first and the pickers
  /// only need the second, so one of them failing must not blank the other —
  /// which is exactly what a single combined await used to do.
  Future<void> _bootstrap() async {
    final api = ref.read(apiClientProvider);

    try {
      final profile = await api.profile();
      if (!mounted) return;
      _name.text = profile.displayName ?? '';
      setState(() {
        _accountName = profile.accountName;
        _config = profile.avatar ?? const AvatarConfig();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = _messageFor(error, 'Could not load your profile'));
    }

    try {
      final options = await api.avatarOptions();
      if (!mounted) return;
      setState(() => _options = options);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _loadError = _messageFor(error, 'Could not load the avatar options'),
      );
    }

    if (!mounted) return;
    setState(() => _loading = false);
    await _refreshPreview();
    await _refreshThumbnails();
  }

  Future<void> _refreshPreview() async {
    try {
      final svg = await ref
          .read(apiClientProvider)
          .avatarPreviewSvg(_config.isEmpty ? null : _config);
      if (mounted) setState(() => _previewSvg = svg.isEmpty ? null : svg);
    } catch (_) {
      // Keep whatever is on screen; the preview is not worth an error banner.
    }
  }

  Future<void> _refreshThumbnails() async {
    final options = _options;
    if (options == null) return;
    final key = _colorKey(_config);
    if (key == _thumbnailColors && _thumbnails.isNotEmpty) return;
    _thumbnailColors = key;

    final api = ref.read(apiClientProvider);
    for (final group in options.groups) {
      for (final slot in group.slots) {
        try {
          final previews = await api.avatarPartSvgs(
            slot.id,
            colors: _config.colors,
          );
          if (!mounted) return;
          setState(() => _thumbnails[slot.id] = previews);
        } catch (_) {
          // A slot without thumbnails still lists its parts by name.
        }
      }
    }
  }

  void _edit(AvatarConfig next) {
    setState(() {
      _config = next;
      _status = null;
    });
    _refreshPreview();
    _refreshThumbnails();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _status = null;
    });
    final trimmed = _name.text.trim();
    final error = await ref
        .read(profileProvider.notifier)
        .save(
          displayName: trimmed.isEmpty ? null : trimmed,
          avatar: _config.isEmpty ? null : _config,
        );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _status = error ?? 'Saved';
      _statusIsError = error != null;
    });
  }

  void _reset() {
    setState(() {
      _config = const AvatarConfig();
      _status = null;
    });
    _refreshPreview();
    _refreshThumbnails();
  }

  void _retry() {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    _bootstrap();
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.movies);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Scaffold(
      backgroundColor: wp.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Header(saving: _saving, onBack: _back, onSave: _loading ? null : _save),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= _twoColumnWidth;
                        final preview = _Preview(
                          svg: _previewSvg,
                          name: _shownName,
                          size: wide ? 260 : 132,
                        );
                        if (!wide) {
                          return ListView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            children: [
                              Center(child: preview),
                              const SizedBox(height: AppSpacing.lg),
                              ..._editorWidgets(),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Doesn't scroll, so it stays with you while the
                            // options move past it.
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: preview,
                            ),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.all(AppSpacing.lg),
                                children: _editorWidgets(),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String get _shownName {
    final typed = _name.text.trim();
    return typed.isNotEmpty ? typed : _accountName;
  }

  List<Widget> _editorWidgets() {
    final wp = context.wp;
    final options = _options;
    return <Widget>[
      if (_loadError != null) ...[
        _Notice(message: _loadError!, onRetry: _retry),
        const SizedBox(height: AppSpacing.lg),
      ],
      _SectionLabel('Display name'),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _name,
        maxLength: _nameMax,
        style: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 14,
          color: wp.text,
        ),
        decoration: InputDecoration(
          hintText: _accountName,
          counterText: '',
          filled: true,
          fillColor: wp.surface2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: wp.line),
          ),
        ),
        onChanged: (_) => setState(() => _status = null),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        _name.text.trim().isEmpty
            ? 'Leave this empty to stay ${_accountName.isEmpty ? "your account name" : _accountName}.'
            : 'Everyone sees you as ${_name.text.trim()}.',
        style: TextStyle(
          fontFamily: AppFonts.sans,
          fontSize: 12,
          color: wp.dim,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),

      if (options != null) ...[
      for (final group in options.groups) ...[
        _SectionLabel(group.label),
        const SizedBox(height: AppSpacing.sm),
        for (final slot in group.slots) ...[
          _PartStrip(
            slot: slot,
            thumbnails: _thumbnails[slot.id] ?? const <String, String>{},
            selectedId: _config.selections[slot.id],
            onPick: (partId) => _edit(_config.withPart(slot.id, partId)),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.sm),
      ],

      for (final slot in options.colors) ...[
        _SectionLabel(slot.label),
        const SizedBox(height: AppSpacing.sm),
        _ColorRow(
          slot: slot,
          swatches: options.palettes[slot.id] ?? const <String>[],
          current: slot.id == 'background'
              ? (_config.background ?? options.defaultBackground)
              : (_config.colors[slot.id] ?? slot.defaultHex),
          onPick: (value) => _edit(
            slot.id == 'background'
                ? _config.withBackground(value)
                : _config.withColor(slot.id, value),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],

      ],

      Divider(color: wp.line),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          TextButton(
            onPressed: _reset,
            child: Text(
              'Reset to my default avatar',
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 13,
                color: wp.dim,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (_status != null)
            Text(
              _status!,
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _statusIsError ? kSemanticRed : wp.text,
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.xl),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.saving, required this.onBack, this.onSave});

  final bool saving;
  final VoidCallback onBack;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: wp.line)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            icon: Icon(Icons.chevron_left, color: wp.text),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Profile',
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: wp.text,
              ),
            ),
          ),
          FilledButton(
            onPressed: saving ? null : onSave,
            child: Text(saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
    );
  }
}

/// Says why the editor is missing something, rather than leaving a blank page
/// to be interpreted.
class _Notice extends StatelessWidget {
  const _Notice({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: wp.surface2,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: wp.line2),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: kSemanticRed),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 13,
                color: wp.text,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.svg, required this.name, required this.size});

  final String? svg;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: wp.surface2,
            border: Border.all(color: wp.line2),
          ),
          clipBehavior: Clip.antiAlias,
          // An empty circle says nothing about why it is empty; initials at
          // least say who this is meant to be.
          child: svg == null
              ? Center(
                  child: Text(
                    initialsOf(name),
                    style: TextStyle(
                      fontFamily: AppFonts.sans,
                      fontSize: size * 0.28,
                      fontWeight: FontWeight.w700,
                      color: wp.dim,
                    ),
                  ),
                )
              : SvgPicture.string(
                  svg!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  semanticsLabel: name,
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: size,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.sans,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: wp.dim,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: AppFonts.sans,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: context.wp.faint,
      ),
    );
  }
}

/// One slot's choices, scrolling sideways inside its own row.
class _PartStrip extends StatelessWidget {
  const _PartStrip({
    required this.slot,
    required this.thumbnails,
    required this.selectedId,
    required this.onPick,
  });

  final AvatarSlot slot;
  final Map<String, String> thumbnails;
  final String? selectedId;
  final void Function(String partId) onPick;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slot.parts.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final part = slot.parts[index];
          final selected = part.id == selectedId;
          final svg = thumbnails[part.id];
          return Tooltip(
            message: part.label,
            child: GestureDetector(
              onTap: () => onPick(part.id),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: wp.surface2,
                  borderRadius: BorderRadius.circular(12),
                  // Selection is a brighter ring, not a colour fill — the same
                  // way the rest of the app marks an active control.
                  border: Border.all(
                    color: selected ? wp.text : wp.line,
                    width: selected ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: svg == null
                    ? Center(
                        child: Text(
                          part.label,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.sans,
                            fontSize: 9,
                            color: wp.dim,
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.all(4),
                        child: SvgPicture.string(svg, fit: BoxFit.contain),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One colour slot's swatches. The web offers a full picker alongside these;
/// here it is the curated set plus, where the asset set allows it, none at all.
class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.slot,
    required this.swatches,
    required this.current,
    required this.onPick,
  });

  final AvatarColorSlot slot;
  final List<String> swatches;
  final String current;
  final void Function(String value) onPick;

  static Color _parse(String hex) {
    final value = int.tryParse(hex.replaceAll('#', ''), radix: 16);
    return value == null ? const Color(0xFF888888) : Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final hex in swatches)
          GestureDetector(
            onTap: () => onPick(hex),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _parse(hex),
                shape: BoxShape.circle,
                border: Border.all(
                  color: current.toUpperCase() == hex.toUpperCase()
                      ? wp.text
                      : wp.line2,
                  width: 2,
                ),
              ),
            ),
          ),
        if (slot.allowTransparent)
          GestureDetector(
            onTap: () => onPick('transparent'),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: current == 'transparent' ? wp.text : wp.line2,
                ),
              ),
              child: Text(
                'None',
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: wp.dim,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
