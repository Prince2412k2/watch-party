import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../analog/chrome/chrome.dart';
import '../../analog/browse_core.dart';
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
  static const _wideWidth = 900.0;

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
  int _focusedRow = 0;
  String? _status;
  bool _statusIsError = false;

  // One counter per independent request family. Every one of these can be
  // restarted (Retry, a part tap, a colour change) while the previous round is
  // still in flight, and the responses arrive in whatever order the network
  // decides. Each request captures the counter it was issued under and drops
  // itself if a newer round has started, so a slow answer can no longer paint
  // over a configuration the user has already moved past.
  int _bootstrapGeneration = 0;
  int _previewGeneration = 0;
  int _thumbnailGeneration = 0;
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
    final generation = ++_bootstrapGeneration;
    final api = ref.read(apiClientProvider);

    try {
      final profile = await api.profile();
      if (!_isCurrent(generation)) return;
      _name.text = profile.displayName ?? '';
      setState(() {
        _accountName = profile.accountName;
        _config = profile.avatar ?? const AvatarConfig();
      });
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(
        () => _loadError = _messageFor(error, 'Could not load your profile'),
      );
    }

    try {
      final options = await api.avatarOptions();
      if (!_isCurrent(generation)) return;
      setState(() {
        _options = options;
        _focusedRow = _rowsFor(options).length ~/ 2;
      });
    } catch (error) {
      if (!_isCurrent(generation)) return;
      setState(
        () => _loadError = _messageFor(
          error,
          'Could not load the avatar options',
        ),
      );
    }

    if (!_isCurrent(generation)) return;
    setState(() => _loading = false);
    await _refreshPreview();
    await _refreshThumbnails();
  }

  /// Whether the round that captured [generation] is still the current one and
  /// this screen is still on screen.
  bool _isCurrent(int generation) =>
      mounted && generation == _bootstrapGeneration;

  Future<void> _refreshPreview() async {
    final generation = ++_previewGeneration;
    // Captured before the await: this is the configuration the answer will
    // describe, and by the time it lands `_config` may be two taps further on.
    final config = _config.isEmpty ? null : _config;
    try {
      final svg = await ref.read(apiClientProvider).avatarPreviewSvg(config);
      if (!mounted || generation != _previewGeneration) return;
      setState(() => _previewSvg = svg.isEmpty ? null : svg);
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

    final generation = ++_thumbnailGeneration;
    // Captured, not read live inside the loop: the previous version reread
    // `_config.colors` per slot, so one colour change mid-walk left the grid
    // holding half the old palette and half the new one.
    final colors = Map<String, String>.from(_config.colors);
    final api = ref.read(apiClientProvider);
    for (final group in options.groups) {
      for (final slot in group.slots) {
        // A colour change starts a new round. The old one has to stop here:
        // it is fetching in the previous palette, and every slot it still has
        // to walk would overwrite the new palette's thumbnails with it.
        if (!mounted || generation != _thumbnailGeneration) return;
        try {
          final previews = await api.avatarPartSvgs(slot.id, colors: colors);
          if (!mounted || generation != _thumbnailGeneration) return;
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
      body: Stack(
        children: [
          const Positioned.fill(child: _ProfileBackground()),
          SafeArea(
            child: Column(
              children: [
                _Header(
                  saving: _saving,
                  onBack: _back,
                  onSave: _loading ? null : _save,
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= _wideWidth;
                            final previewSize = wide
                                ? (constraints.maxWidth * 0.25).clamp(
                                    300.0,
                                    420.0,
                                  )
                                : (constraints.maxWidth - 64).clamp(
                                    180.0,
                                    260.0,
                                  );
                            final preview = _Preview(
                              svg: _previewSvg,
                              name: _shownName,
                              size: previewSize,
                            );

                            if (!wide) {
                              return ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  16,
                                  24,
                                  48,
                                ),
                                children: [
                                  Center(child: preview),
                                  const SizedBox(height: AppSpacing.xl),
                                  SizedBox(
                                    height: 560,
                                    child: _editor(compact: true),
                                  ),
                                ],
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.fromLTRB(
                                44,
                                12,
                                52,
                                36,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Align(
                                      alignment: const Alignment(0, -0.18),
                                      child: preview,
                                    ),
                                  ),
                                  const SizedBox(width: 48),
                                  Expanded(
                                    flex: 6,
                                    child: _editor(compact: false),
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
        ],
      ),
    );
  }

  String get _shownName {
    final typed = _name.text.trim();
    return typed.isNotEmpty ? typed : _accountName;
  }

  Widget _editor({required bool compact}) {
    final options = _options;
    final rows = options == null ? const <_EditorRow>[] : _rowsFor(options);
    final optionRows = <Widget>[
      if (_loadError != null) ...[
        _Notice(message: _loadError!, onRetry: _retry),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (options != null)
        for (final row in rows)
          _OptionRow(
            compact: compact,
            group: row.group,
            colorSlot: row.color,
            palettes: options.palettes,
            defaultBackground: options.defaultBackground,
            config: _config,
            thumbnails: _thumbnails,
            onEdit: _edit,
          ),
    ];

    return Column(
      key: const ValueKey('profile-editor-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _FocusedRowRail(
            focusedIndex: _focusedRow,
            onFocusedChanged: (index) => setState(() => _focusedRow = index),
            onHorizontalStep: _stepFocusedChoice,
            children: optionRows,
          ),
        ),
        _EditorFooter(
          status: _status,
          statusIsError: _statusIsError,
          onReset: _reset,
        ),
      ],
    );
  }

  List<_EditorRow> _rowsFor(AvatarOptions options) {
    const colorForGroup = <String, String>{
      'head': 'hair',
      'body': 'clothes',
      'bottom': 'bottom',
      'glasses': 'stroke',
      'item': 'background',
    };
    final groups = {for (final group in options.groups) group.id: group};
    final colors = {for (final color in options.colors) color.id: color};
    final usedGroups = <String>{};
    final usedColors = <String>{};
    final rows = <_EditorRow>[];

    for (final pair in colorForGroup.entries) {
      final group = groups[pair.key];
      final color = colors[pair.value];
      if (group == null && color == null) continue;
      rows.add(_EditorRow(group: group, color: color));
      if (group != null) usedGroups.add(group.id);
      if (color != null) usedColors.add(color.id);
    }
    for (final group in options.groups) {
      if (!usedGroups.contains(group.id)) rows.add(_EditorRow(group: group));
    }
    for (final color in options.colors) {
      if (!usedColors.contains(color.id)) rows.add(_EditorRow(color: color));
    }
    return rows;
  }

  void _stepFocusedChoice(int direction) {
    final options = _options;
    if (options == null) return;
    final rows = _rowsFor(options);
    if (rows.isEmpty) return;
    final slots = rows[_focusedRow % rows.length].group?.slots;
    if (slots == null || slots.isEmpty) return;
    final slot = slots.first;
    if (slot.parts.isEmpty) return;
    final currentId = _config.selections[slot.id];
    final current = slot.parts.indexWhere((part) => part.id == currentId);
    final next = current < 0
        ? (direction > 0 ? 0 : slot.parts.length - 1)
        : (current + direction) % slot.parts.length;
    _edit(_config.withPart(slot.id, slot.parts[next].id));
  }
}

class _EditorRow {
  const _EditorRow({this.group, this.color});

  final AvatarGroup? group;
  final AvatarColorSlot? color;
}

double profileRowScaleAt(int distance) {
  final step = distance.abs().clamp(0, 2);
  return 1 - step * 0.165;
}

double profileRowOpacityAt(int distance) {
  return switch (distance.abs().clamp(0, 2)) {
    0 => 1,
    1 => 0.68,
    _ => 0.44,
  };
}

int profileCircularDistance(int index, int focusedIndex, int total) {
  if (total < 2) return 0;
  final forward = (index - focusedIndex) % total;
  final backward = forward - total;
  return forward <= -backward ? forward : backward;
}

class _FocusedRowRail extends StatefulWidget {
  const _FocusedRowRail({
    required this.focusedIndex,
    required this.onFocusedChanged,
    required this.onHorizontalStep,
    required this.children,
  });

  final int focusedIndex;
  final ValueChanged<int> onFocusedChanged;
  final ValueChanged<int> onHorizontalStep;
  final List<Widget> children;

  @override
  State<_FocusedRowRail> createState() => _FocusedRowRailState();
}

class _FocusedRowRailState extends State<_FocusedRowRail> {
  static const _rowExtent = 176.0;

  final _focusNode = FocusNode(debugLabel: 'Profile row rail');
  final _scrollState = SteppedScrollState();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _step(int direction) {
    if (widget.children.isEmpty) return;
    widget.onFocusedChanged(
      (widget.focusedIndex + direction) % widget.children.length,
    );
  }

  void _scroll(Offset delta) {
    if (delta.dx.abs() > delta.dy.abs()) return;
    final step = steppedScroll(
      _scrollState,
      delta.dy,
      DateTime.now().millisecondsSinceEpoch.toDouble(),
      kSteppedScrollDefaults,
    );
    if (step == 0) return;
    _focusNode.requestFocus();
    _step(step);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      _scroll((resolved as PointerScrollEvent).scrollDelta);
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        _step(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _step(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        widget.onHorizontalStep(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        widget.onHorizontalStep(1);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.expand();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 320);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomUpdate: (event) => _scroll(-event.localPanDelta),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final centerY = constraints.maxHeight / 2;
            final stride = (constraints.maxHeight - _rowExtent) / 4;
            return ClipRect(
              child: Stack(
                children: [
                  for (var index = 0; index < widget.children.length; index++)
                    () {
                      final distance = profileCircularDistance(
                        index,
                        widget.focusedIndex,
                        widget.children.length,
                      );
                      final focused = distance == 0;
                      final visible = distance.abs() <= 2;
                      final parkedDistance = distance.sign * 3;
                      return AnimatedPositioned(
                        key: ValueKey('profile-row-$index'),
                        duration: duration,
                        curve: AppMotion.emphasized,
                        left: 0,
                        right: 0,
                        top:
                            centerY -
                            _rowExtent / 2 +
                            (visible ? distance : parkedDistance) * stride,
                        height: _rowExtent,
                        child: AnimatedScale(
                          scale: profileRowScaleAt(distance),
                          duration: duration,
                          curve: AppMotion.emphasized,
                          child: AnimatedOpacity(
                            opacity: visible
                                ? profileRowOpacityAt(distance)
                                : 0,
                            duration: duration,
                            curve: AppMotion.standard,
                            child: Semantics(
                              selected: focused,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: focused
                                    ? null
                                    : () => widget.onFocusedChanged(index),
                                child: IgnorePointer(
                                  ignoring: !focused || !visible,
                                  child: widget.children[index],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({
    required this.status,
    required this.statusIsError,
    required this.onReset,
  });

  final String? status;
  final bool statusIsError;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        children: [
          AnalogButton(
            label: 'Reset to my default avatar',
            tone: AnalogButtonTone.ghost,
            dense: true,
            onPressed: onReset,
          ),
          const SizedBox(width: AppSpacing.md),
          if (status != null)
            Text(
              status!,
              style: TextStyle(
                fontFamily: AppFonts.sans,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: statusIsError ? kSemanticRed : wp.text,
              ),
            ),
        ],
      ),
    );
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
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
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
          _SaveButton(saving: saving, onPressed: onSave),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, this.onPressed});

  final bool saving;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return SizedBox(
      width: 108,
      height: 54,
      child: OutlinedButton(
        onPressed: saving ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: wp.text,
          backgroundColor: wp.surface.withValues(alpha: 0.5),
          disabledForegroundColor: wp.faint,
          side: BorderSide(color: wp.line2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          textStyle: const TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(saving ? 'Saving...' : 'Save'),
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
          AnalogButton(
            label: 'Retry',
            tone: AnalogButtonTone.ghost,
            dense: true,
            onPressed: onRetry,
          ),
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
    return Container(
      key: const ValueKey('profile-avatar-stage'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF101216),
        border: Border.all(color: wp.line2),
      ),
      clipBehavior: Clip.antiAlias,
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
    );
  }
}

class _ProfileBackground extends StatelessWidget {
  const _ProfileBackground();

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.1, -0.05),
          radius: 1.15,
          colors: [wp.surface.withValues(alpha: 0.72), wp.bg],
          stops: const [0, 0.82],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.compact,
    required this.group,
    required this.colorSlot,
    required this.palettes,
    required this.defaultBackground,
    required this.config,
    required this.thumbnails,
    required this.onEdit,
  });

  final bool compact;
  final AvatarGroup? group;
  final AvatarColorSlot? colorSlot;
  final Map<String, List<String>> palettes;
  final String defaultBackground;
  final AvatarConfig config;
  final Map<String, Map<String, String>> thumbnails;
  final ValueChanged<AvatarConfig> onEdit;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final swatches = colorSlot == null
        ? const <String>[]
        : palettes[colorSlot!.id] ?? const <String>[];
    final current = colorSlot == null
        ? ''
        : colorSlot!.id == 'background'
        ? config.background ?? defaultBackground
        : config.colors[colorSlot!.id] ?? colorSlot!.defaultHex;

    final colors = _ColorWheel(
      slot: colorSlot,
      presets: swatches,
      current: current,
      onPick: (value) {
        final slot = colorSlot!;
        onEdit(
          slot.id == 'background'
              ? config.withBackground(value)
              : config.withColor(slot.id, value),
        );
      },
    );
    final parts = _Parts(
      group: group,
      config: config,
      thumbnails: thumbnails,
      onEdit: onEdit,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 172),
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: wp.line)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: compact ? 76 : 120,
            child: Center(child: colors),
          ),
          SizedBox(width: compact ? 14 : 30),
          Expanded(child: SizedBox(height: 116, child: parts)),
        ],
      ),
    );
  }
}

class _ColorWheel extends StatelessWidget {
  const _ColorWheel({
    required this.slot,
    required this.presets,
    required this.current,
    required this.onPick,
  });

  final AvatarColorSlot? slot;
  final List<String> presets;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (slot == null) return const SizedBox.shrink();
    final wp = context.wp;
    return Tooltip(
      message: 'Choose ${slot!.label.toLowerCase()} color',
      child: Semantics(
        button: true,
        label: 'Choose ${slot!.label.toLowerCase()} color',
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            radius: 32,
            onTap: () async {
              final selected = await showDialog<String>(
                context: context,
                builder: (context) => _PresetColorDialog(
                  slot: slot!,
                  presets: presets,
                  current: current,
                ),
              );
              if (selected != null) onPick(selected);
            },
            child: Container(
              key: ValueKey('profile-color-wheel-${slot!.id}'),
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    Color(0xFFE0655E),
                    Color(0xFFF2C94C),
                    Color(0xFF78C99F),
                    Color(0xFF6E9FE8),
                    Color(0xFFA779D8),
                    Color(0xFFE0655E),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: wp.shadow,
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: wp.bg, shape: BoxShape.circle),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: current == 'transparent'
                        ? Colors.transparent
                        : _avatarColor(current),
                    shape: BoxShape.circle,
                    border: Border.all(color: wp.line2),
                  ),
                  child: current == 'transparent'
                      ? Icon(Icons.block, size: 20, color: wp.dim)
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetColorDialog extends StatelessWidget {
  const _PresetColorDialog({
    required this.slot,
    required this.presets,
    required this.current,
  });

  final AvatarColorSlot slot;
  final List<String> presets;
  final String current;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Dialog(
      backgroundColor: wp.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        side: BorderSide(color: wp.line2),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 390),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slot.label,
                style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: wp.text,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final hex in presets)
                    _PresetColor(
                      hex: hex,
                      label: '${slot.label} #$hex',
                      selected: current.toUpperCase() == hex.toUpperCase(),
                    ),
                  if (slot.allowTransparent)
                    _PresetColor(
                      hex: 'transparent',
                      label: 'No ${slot.label.toLowerCase()} color',
                      selected: current == 'transparent',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetColor extends StatelessWidget {
  const _PresetColor({
    required this.hex,
    required this.label,
    required this.selected,
  });

  final String hex;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkResponse(
          radius: 30,
          onTap: () => Navigator.of(context).pop(hex),
          child: Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? wp.text : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: hex == 'transparent'
                    ? Colors.transparent
                    : _avatarColor(hex),
                shape: BoxShape.circle,
                border: Border.all(color: wp.line2),
              ),
              child: hex == 'transparent'
                  ? Icon(Icons.block, size: 22, color: wp.dim)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

Color _avatarColor(String hex) {
  final value = int.tryParse(hex.replaceAll('#', ''), radix: 16);
  return value == null ? const Color(0xFF888888) : Color(0xFF000000 | value);
}

class _Parts extends StatefulWidget {
  const _Parts({
    required this.group,
    required this.config,
    required this.thumbnails,
    required this.onEdit,
  });

  final AvatarGroup? group;
  final AvatarConfig config;
  final Map<String, Map<String, String>> thumbnails;
  final ValueChanged<AvatarConfig> onEdit;

  @override
  State<_Parts> createState() => _PartsState();
}

class _PartsState extends State<_Parts> {
  static const _stride = 130.0;

  final _scroll = ScrollController();

  List<({AvatarSlot slot, AvatarPart part})> get _choices {
    final slots = widget.group?.slots ?? const <AvatarSlot>[];
    return <({AvatarSlot slot, AvatarPart part})>[
      for (final slot in slots)
        for (final part in slot.parts) (slot: slot, part: part),
    ];
  }

  @override
  void didUpdateWidget(_Parts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.selections != widget.config.selections) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _revealSelected() {
    if (!mounted || !_scroll.hasClients) return;
    final choices = _choices;
    final selected = choices.indexWhere(
      (choice) => widget.config.selections[choice.slot.id] == choice.part.id,
    );
    if (selected < 0) return;
    final position = _scroll.position;
    final start = selected * _stride;
    final end = start + 112;
    var target = position.pixels;
    if (start < target) {
      target = start;
    } else if (end > target + position.viewportDimension) {
      target = end - position.viewportDimension;
    }
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return;
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: AppMotion.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    if (choices.isEmpty) return const SizedBox.shrink();

    return ListView.separated(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      itemCount: choices.length,
      separatorBuilder: (_, _) => const SizedBox(width: 18),
      itemBuilder: (context, index) {
        final choice = choices[index];
        final svg = widget.thumbnails[choice.slot.id]?[choice.part.id];
        final selected =
            widget.config.selections[choice.slot.id] == choice.part.id;
        return _PartChoice(
          label: choice.part.label,
          svg: svg,
          selected: selected,
          onTap: () => widget.onEdit(
            widget.config.withPart(choice.slot.id, choice.part.id),
          ),
        );
      },
    );
  }
}

class _PartChoice extends StatelessWidget {
  const _PartChoice({
    required this.label,
    required this.svg,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? svg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 112,
            height: 112,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? wp.text : Colors.transparent,
              ),
            ),
            child: svg == null
                ? Center(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppFonts.sans,
                        fontSize: 10,
                        color: wp.dim,
                      ),
                    ),
                  )
                : SvgPicture.string(svg!, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
