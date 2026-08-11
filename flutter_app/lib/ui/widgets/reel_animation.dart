import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The reel: eight seats orbiting a red disc, filling and emptying like a room
/// does, with the crown moving between them.
///
/// A port of `reel.svg`, not an embedding of it. That file draws itself with a
/// CSS keyframe for the spin, CSS transitions per seat, and a script that
/// builds the seats and runs the room's lifecycle. `flutter_svg` renders none
/// of the three — it would have shown a bare red disc, because even the seats
/// only exist once the script has run.
///
/// The geometry is the SVG's, unchanged: a 600×600 box, seats on a 160 orbit,
/// 36 heads, shoulders that reach past the 205 disc edge.
class ReelAnimation extends StatefulWidget {
  const ReelAnimation({super.key});

  /// The SVG's viewBox. Everything below is in these units and scaled to fit.
  static const double _box = 600;
  static const double _centre = 300;
  static const double _orbit = 160;
  static const double _headRadius = 36;
  static const double _discRadius = 205;
  static const int _seatCount = 8;

  static const Color _disc = Color(0xFFFD2C3F);
  static const Color _discEdge = Color(0xFFD91F31);
  static const Color _ink = Color(0xFF1E1415);
  static const Color _cream = Color(0xFFF8F3EF);
  static const Color _hostStroke = Color(0xFF0B0708);

  @override
  State<ReelAnimation> createState() => _ReelAnimationState();
}

enum _SeatState { empty, guest, host }

/// How a seat looks once it has settled into a state. Every visible difference
/// between empty, guest and host lives here, so the painter only ever lerps.
@immutable
class _SeatLook {
  const _SeatLook({
    required this.headScale,
    required this.headFill,
    required this.headStroke,
    required this.headStrokeOpacity,
    required this.bodyScaleX,
    required this.bodyScaleY,
    required this.bodyOpacity,
    required this.bodyFill,
    required this.bodyStroke,
    required this.bodyStrokeOpacity,
  });

  final double headScale;
  final Color headFill;
  final Color headStroke;
  final double headStrokeOpacity;
  final double bodyScaleX;
  final double bodyScaleY;
  final double bodyOpacity;
  final Color bodyFill;
  final Color bodyStroke;
  final double bodyStrokeOpacity;

  static const _SeatLook empty = _SeatLook(
    headScale: 0.9,
    headFill: ReelAnimation._ink,
    headStroke: ReelAnimation._cream,
    headStrokeOpacity: 0,
    bodyScaleX: 0.6,
    bodyScaleY: 0,
    bodyOpacity: 0,
    bodyFill: ReelAnimation._ink,
    bodyStroke: ReelAnimation._ink,
    bodyStrokeOpacity: 0,
  );

  static const _SeatLook guest = _SeatLook(
    headScale: 1,
    headFill: ReelAnimation._ink,
    headStroke: ReelAnimation._cream,
    headStrokeOpacity: 1,
    bodyScaleX: 1,
    bodyScaleY: 1,
    bodyOpacity: 1,
    bodyFill: ReelAnimation._ink,
    bodyStroke: ReelAnimation._ink,
    bodyStrokeOpacity: 0,
  );

  static const _SeatLook host = _SeatLook(
    headScale: 1.04,
    headFill: ReelAnimation._cream,
    headStroke: ReelAnimation._hostStroke,
    headStrokeOpacity: 1,
    bodyScaleX: 1,
    bodyScaleY: 1,
    bodyOpacity: 1,
    bodyFill: ReelAnimation._cream,
    bodyStroke: ReelAnimation._hostStroke,
    bodyStrokeOpacity: 1,
  );

  static _SeatLook of(_SeatState state) => switch (state) {
    _SeatState.empty => empty,
    _SeatState.guest => guest,
    _SeatState.host => host,
  };

  static _SeatLook lerp(_SeatLook a, _SeatLook b, double t, double motionT) {
    return _SeatLook(
      headScale: _lerp(a.headScale, b.headScale, motionT),
      headFill: Color.lerp(a.headFill, b.headFill, t)!,
      headStroke: Color.lerp(a.headStroke, b.headStroke, t)!,
      headStrokeOpacity: _lerp(a.headStrokeOpacity, b.headStrokeOpacity, t),
      bodyScaleX: _lerp(a.bodyScaleX, b.bodyScaleX, motionT),
      bodyScaleY: _lerp(a.bodyScaleY, b.bodyScaleY, motionT),
      bodyOpacity: _lerp(a.bodyOpacity, b.bodyOpacity, t),
      bodyFill: Color.lerp(a.bodyFill, b.bodyFill, t)!,
      bodyStroke: Color.lerp(a.bodyStroke, b.bodyStroke, t)!,
      bodyStrokeOpacity: _lerp(a.bodyStrokeOpacity, b.bodyStrokeOpacity, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}

class _Seat {
  _Seat();

  _SeatState state = _SeatState.empty;
  _SeatState from = _SeatState.empty;

  /// When the current transition began, on the ticker's clock.
  Duration changedAt = Duration.zero;

  /// When the crown last landed here, or null. Drives the one-shot flash.
  Duration? promotedAt;

  void moveTo(_SeatState next, Duration now) {
    if (state == next) return;
    from = state;
    state = next;
    changedAt = now;
  }
}

class _ReelAnimationState extends State<ReelAnimation>
    with SingleTickerProviderStateMixin {
  /// One clock for everything. The spin, the hub's breathing and each seat's
  /// transition are all read off the same elapsed time, so there are no
  /// controllers to keep in step with one another.
  late final Ticker _ticker;
  Duration _now = Duration.zero;

  final _seats = List.generate(ReelAnimation._seatCount, (_) => _Seat());
  final _random = math.Random();

  /// The room's lifecycle, straight from the SVG's script.
  String _phase = 'filling';
  int _busyLeft = 0;
  int _target = 0;
  Duration _nextTick = Duration.zero;

  static const Duration _transition = Duration(milliseconds: 300);
  static const Duration _promoteFlash = Duration(milliseconds: 450);
  static const Duration _spin = Duration(seconds: 26);
  static const Duration _breathe = Duration(milliseconds: 2200);

  @override
  void initState() {
    super.initState();
    _startRoom();
    _nextTick = const Duration(milliseconds: 650);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    if (elapsed >= _nextTick) _step();
    setState(() {});
  }

  List<_Seat> _of(_SeatState state) =>
      _seats.where((s) => s.state == state).toList();

  _Seat _pick(List<_Seat> list) => list[_random.nextInt(list.length)];

  void _promote(_Seat seat) {
    seat.moveTo(_SeatState.host, _now);
    seat.promotedAt = _now;
  }

  void _startRoom() {
    for (final seat in _seats) {
      seat.moveTo(_SeatState.empty, _now);
    }
    _promote(_pick(_seats));
    _phase = 'filling';
    _target = 4 + _random.nextInt(4);
  }

  void _schedule(int ms) => _nextTick = _now + Duration(milliseconds: ms);

  /// The room's behaviour, ported beat for beat: it fills to a target, holds
  /// busy for a while with the crown changing hands, then drains back down to
  /// whoever is left holding it.
  void _step() {
    final empty = _of(_SeatState.empty);
    final guests = _of(_SeatState.guest);
    final hosts = _of(_SeatState.host);
    final r = _random.nextDouble();

    if (_phase == 'filling') {
      if (guests.length >= _target || empty.isEmpty) {
        _phase = 'busy';
        _busyLeft = 5 + _random.nextInt(7);
      } else if (r < 0.8 && empty.isNotEmpty) {
        _pick(empty).moveTo(_SeatState.guest, _now);
      } else if (guests.isNotEmpty) {
        _pick(guests).moveTo(_SeatState.empty, _now);
      }
    } else if (_phase == 'busy') {
      _busyLeft--;
      if (_busyLeft <= 0) {
        _phase = 'draining';
      } else if (r < 0.3 && guests.isNotEmpty) {
        // The host hands the room over and stays on as a guest.
        final next = _pick(guests);
        if (hosts.isNotEmpty) hosts.first.moveTo(_SeatState.guest, _now);
        _promote(next);
      } else if (r < 0.62 && empty.isNotEmpty) {
        _pick(empty).moveTo(_SeatState.guest, _now);
      } else if (guests.isNotEmpty) {
        _pick(guests).moveTo(_SeatState.empty, _now);
      }
    } else {
      if (guests.isNotEmpty) {
        if (r < 0.2 && hosts.isNotEmpty) {
          // The host drops off, passing the crown on the way out.
          final heir = _pick(guests);
          hosts.first.moveTo(_SeatState.empty, _now);
          _promote(heir);
        } else {
          _pick(guests).moveTo(_SeatState.empty, _now);
        }
      } else {
        // Only the host is left. Hold a beat, then fill up again.
        _phase = 'filling';
        _target = 4 + _random.nextInt(4);
        if (hosts.isEmpty) _startRoom();
        _schedule(750);
        return;
      }
    }

    _schedule(280 + _random.nextInt(480));
  }

  @override
  Widget build(BuildContext context) {
    // A viewer who asked for less motion gets the room without the carousel:
    // the reel stops turning and seats change without the springy overshoot.
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final spin = still
        ? 0.0
        : (_now.inMicroseconds % _spin.inMicroseconds) /
              _spin.inMicroseconds *
              2 *
              math.pi;

    final breathePhase = still
        ? 0.0
        : (_now.inMicroseconds % _breathe.inMicroseconds) /
              _breathe.inMicroseconds;
    // 1 → 1.12 → 1, the SVG's ease-in-out breathe.
    final breathe = still
        ? 1.0
        : 1 + 0.12 * (0.5 - 0.5 * math.cos(breathePhase * 2 * math.pi));

    final looks = <_SeatLook>[];
    for (final seat in _seats) {
      final elapsed = _now - seat.changedAt;
      final raw = still
          ? 1.0
          : (elapsed.inMicroseconds / _transition.inMicroseconds).clamp(
              0.0,
              1.0,
            );
      final look = _SeatLook.lerp(
        _SeatLook.of(seat.from),
        _SeatLook.of(seat.state),
        Curves.easeOut.transform(raw),
        // The SVG springs its transforms; colours just ease.
        still ? 1.0 : Curves.easeOutBack.transform(raw),
      );
      looks.add(_withPromoteFlash(seat, look, still));
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: _ReelPainter(spin: spin, breathe: breathe, looks: looks),
        size: Size.square(ReelAnimation._box),
      ),
    );
  }

  /// The crown landing is worth a beat of its own: the head kicks past its
  /// resting size and settles back, so a handoff is visible even when you were
  /// not watching that seat.
  _SeatLook _withPromoteFlash(_Seat seat, _SeatLook look, bool still) {
    final at = seat.promotedAt;
    if (still || at == null || seat.state != _SeatState.host) return look;
    final elapsed = _now - at;
    if (elapsed >= _promoteFlash) return look;

    final t = elapsed.inMicroseconds / _promoteFlash.inMicroseconds;
    // 0% 1.0 → 45% 1.22 → 100% 1.04
    final scale = t < 0.45
        ? 1.0 + (1.22 - 1.0) * Curves.easeOut.transform(t / 0.45)
        : 1.22 + (1.04 - 1.22) * Curves.easeOutBack.transform((t - 0.45) / 0.55);

    return _SeatLook(
      headScale: scale,
      headFill: look.headFill,
      headStroke: look.headStroke,
      headStrokeOpacity: look.headStrokeOpacity,
      bodyScaleX: look.bodyScaleX,
      bodyScaleY: look.bodyScaleY,
      bodyOpacity: look.bodyOpacity,
      bodyFill: look.bodyFill,
      bodyStroke: look.bodyStroke,
      bodyStrokeOpacity: look.bodyStrokeOpacity,
    );
  }
}

class _ReelPainter extends CustomPainter {
  _ReelPainter({
    required this.spin,
    required this.breathe,
    required this.looks,
  });

  final double spin;
  final double breathe;
  final List<_SeatLook> looks;

  /// The shoulders, in pod-local space: +Y points away from the disc. Copied
  /// from the SVG's `#body` path.
  static final Path _body = Path()
    ..moveTo(-8.9, 53)
    ..cubicTo(-38.5, 53, -62.5, 77, -62.5, 106.8)
    ..cubicTo(-62.5, 111.8, -58.5, 115.8, -53.6, 115.8)
    ..lineTo(53.6, 115.8)
    ..cubicTo(58.5, 115.8, 62.5, 111.8, 62.5, 106.8)
    ..cubicTo(62.5, 77, 38.5, 53, 8.9, 53)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is written in the SVG's 600-unit box.
    final scale = size.shortestSide / ReelAnimation._box;
    canvas.save();
    canvas.scale(scale);

    canvas.translate(ReelAnimation._centre, ReelAnimation._centre);
    canvas.rotate(spin);

    canvas.drawCircle(
      Offset.zero,
      ReelAnimation._discRadius,
      Paint()..color = ReelAnimation._disc,
    );
    canvas.drawCircle(
      Offset.zero,
      ReelAnimation._discRadius,
      Paint()
        ..color = ReelAnimation._discEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    for (var i = 0; i < looks.length; i++) {
      canvas.save();
      canvas.rotate(i * 2 * math.pi / ReelAnimation._seatCount);
      canvas.translate(0, ReelAnimation._orbit);
      _paintSeat(canvas, looks[i]);
      canvas.restore();
    }

    // The hub sits above the seats, and its ring breathes.
    canvas.drawCircle(Offset.zero, 20, Paint()..color = ReelAnimation._ink);
    canvas.drawCircle(
      Offset.zero,
      17.5 * breathe,
      Paint()..color = ReelAnimation._cream,
    );

    canvas.restore();
  }

  void _paintSeat(Canvas canvas, _SeatLook look) {
    // Shoulders first — the head overlaps them.
    if (look.bodyOpacity > 0.001 && look.bodyScaleY > 0.001) {
      canvas.save();
      // The SVG scales the body from the top of its own box (y = 53), so it
      // grows out of the head rather than out of thin air.
      canvas.translate(0, 53);
      canvas.scale(look.bodyScaleX, look.bodyScaleY);
      canvas.translate(0, -53);

      canvas.drawPath(
        _body,
        Paint()..color = _fade(look.bodyFill, look.bodyOpacity),
      );
      if (look.bodyStrokeOpacity > 0.001) {
        canvas.drawPath(
          _body,
          Paint()
            ..color = _fade(
              look.bodyStroke,
              look.bodyOpacity * look.bodyStrokeOpacity,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }
      canvas.restore();
    }

    final r = ReelAnimation._headRadius * look.headScale;
    canvas.drawCircle(Offset.zero, r, Paint()..color = look.headFill);
    if (look.headStrokeOpacity > 0.001) {
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..color = _fade(look.headStroke, look.headStrokeOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  static Color _fade(Color c, double opacity) =>
      c.withValues(alpha: c.a * opacity.clamp(0.0, 1.0));

  @override
  bool shouldRepaint(_ReelPainter old) => true;
}
