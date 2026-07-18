import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../palette.dart';
import '../theme.dart';

/// A focusable horizontal poster shelf with one selected title. Pointer scroll,
/// dragging, and arrow keys all update the same selection model.
class PosterShelf extends StatefulWidget {
  const PosterShelf({
    super.key,
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.onSelectionChanged,
    this.onActivate,
    this.onMovementSound,
    this.autofocus = false,
    this.itemWidth = 190,
    this.spacing = 16,
    this.leftInset = 0,
    this.fillAvailableHeight = false,
  });

  final String title;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final ValueChanged<int>? onSelectionChanged;
  final ValueChanged<int>? onActivate;
  final VoidCallback? onMovementSound;
  final bool autofocus;
  final double itemWidth;
  final double spacing;
  final double leftInset;
  final bool fillAvailableHeight;

  @override
  State<PosterShelf> createState() => _PosterShelfState();
}

class _PosterShelfState extends State<PosterShelf> {
  final _controller = ScrollController();
  final _focusNode = FocusNode();
  var _selectedIndex = 0;
  var _canScrollLeft = false;
  var _canScrollRight = true;
  var _programmaticScroll = false;
  DateTime? _lastWheelMove;

  double get _stride => widget.itemWidth + widget.spacing;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(PosterShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    final last = widget.itemCount - 1;
    if (_selectedIndex > last) {
      _selectedIndex = last < 0 ? 0 : last;
    }
  }

  void _onScroll() {
    if (!_controller.hasClients || widget.itemCount == 0) return;
    final position = _controller.position;
    final next = _programmaticScroll
        ? _selectedIndex
        : (_controller.offset / _stride).round().clamp(0, widget.itemCount - 1);
    final canLeft = position.pixels > position.minScrollExtent + 1;
    final canRight = position.pixels < position.maxScrollExtent - 1;
    if (next != _selectedIndex ||
        canLeft != _canScrollLeft ||
        canRight != _canScrollRight) {
      setState(() {
        if (next != _selectedIndex) {
          _selectedIndex = next;
          widget.onSelectionChanged?.call(next);
          _playMovementSound();
        }
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _playMovementSound() {
    if (widget.onMovementSound != null) {
      widget.onMovementSound!();
    } else {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
  }

  void _select(
    int index, {
    bool animate = true,
    bool scroll = true,
    bool playSound = true,
  }) {
    if (widget.itemCount == 0) return;
    final next = index.clamp(0, widget.itemCount - 1);
    if (next == _selectedIndex) return;
    setState(() => _selectedIndex = next);
    widget.onSelectionChanged?.call(next);
    if (playSound) _playMovementSound();
    if (!scroll || !_controller.hasClients) return;
    final target = (next * _stride).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    if (animate) {
      _programmaticScroll = true;
      unawaited(
        _controller
            .animateTo(
              target,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() => _programmaticScroll = false),
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _select(_selectedIndex + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _select(_selectedIndex - 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      widget.onActivate?.call(_selectedIndex);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onPointerSignal(PointerSignalEvent signal) {
    if (signal is! PointerScrollEvent || widget.itemCount < 2) return;
    final now = DateTime.now();
    if (_lastWheelMove != null &&
        now.difference(_lastWheelMove!) < const Duration(milliseconds: 120)) {
      return;
    }
    final delta = signal.scrollDelta.dx.abs() > signal.scrollDelta.dy.abs()
        ? signal.scrollDelta.dx
        : signal.scrollDelta.dy;
    if (delta.abs() < 2) return;
    _lastWheelMove = now;
    _select(_selectedIndex + (delta > 0 ? 1 : -1));
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.wp;
    final heading = Padding(
      padding: EdgeInsets.only(left: widget.leftInset, right: 24),
      child: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.headlineLarge.copyWith(color: wp.text),
      ),
    );
    final rail = Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: Listener(
        onPointerDown: (_) => _focusNode.requestFocus(),
        onPointerSignal: _onPointerSignal,
        child: SizedBox(
          height: _railHeight,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                _canScrollLeft ? Colors.transparent : Colors.black,
                Colors.black,
                Colors.black,
                _canScrollRight ? Colors.transparent : Colors.black,
              ],
              stops: const [0, 0.035, 0.965, 1],
            ).createShader(bounds),
            child: ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              padding: EdgeInsets.only(
                left: widget.leftInset,
                right: 40,
                top: 24,
                bottom: 30,
              ),
              itemCount: widget.itemCount,
              separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
              itemBuilder: (context, index) {
                final selected = index == _selectedIndex;
                return MouseRegion(
                  key: ValueKey('poster-shelf-item-$index'),
                  onEnter: (_) {
                    _focusNode.requestFocus();
                    _select(index, scroll: false, playSound: false);
                  },
                  child: Semantics(
                    selected: selected,
                    child: AnimatedScale(
                      scale: selected ? 1.1 : 1,
                      alignment: Alignment.bottomCenter,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: widget.itemBuilder(context, index),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: widget.fillAvailableHeight
          ? MainAxisSize.max
          : MainAxisSize.min,
      children: [
        heading,
        if (widget.fillAvailableHeight)
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: rail),
          )
        else ...[
          const SizedBox(height: 12),
          rail,
        ],
      ],
    );
  }

  double get _railHeight {
    final artHeight = widget.itemWidth * 5 / 3;
    return artHeight + 68 + 58;
  }
}
