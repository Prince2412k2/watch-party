import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The reel: a film disc spinning under a shutter, with people boarding the
/// seats whenever it looks slow enough to step onto.
///
/// A port of `animate/reel.svg`, not an embedding of it. That file spins from
/// script, transitions each seat in CSS, and builds the seats, the perforations
/// and the whole strobe engine at runtime. `flutter_svg` runs none of it — it
/// would have drawn a bare red disc, because nothing on the ring exists until
/// the script has.
///
/// The illusion is not scripted, in the SVG or here. The reel is given a real
/// angular velocity with real inertia, and then only *looked at* once per
/// shutter interval. Because the ring is eight-fold symmetric, the shutter
/// cannot tell a 45° jump from standing still: just under that rate the
/// perforations crawl forward, just over it they crawl backwards. Sweeping the
/// speed up and down through sync plays the whole "speeds up, stalls, runs
/// backwards" cycle in the right order, forever, with nothing sequencing it.
///
/// The streak rings are drawn at the TRUE angle and the ring at the SAMPLED
/// one. Their disagreement is the point: it reads as far too fast to follow
/// even while the marks appear to crawl.
class ReelAnimation extends StatefulWidget {
  const ReelAnimation({super.key});

  /// The SVG's viewBox. Everything below is in these units and scaled to fit.
  static const double _box = 600;
  static const double _orbit = 160;

  /// The seat cut into the reel, and the person in it. The 5px difference is
  /// the outline — there is no stroke anywhere on a seat.
  static const double _hole = 36;
  static const double _head = 31;

  static const double _discRadius = 205;
  static const int _seatCount = 8;

  static const Color _ink = Color(0xFF2E1B2C);
  static const Color _cream = Color(0xFFFAF2E4);
  static const Color _red = Color(0xFFFD2C3F);
  static const Color _redEdge = Color(0xFFD91F31);

  @override
  State<ReelAnimation> createState() => _ReelAnimationState();
}

/// One of the dashed speed rings in the annulus between hub and seats.
@immutable
class _Streak {
  const _Streak({
    required this.radius,
    required this.width,
    required this.opacity,
    required this.dash,
    required this.gap,
    required this.rate,
  });

  final double radius;
  final double width;
  final double opacity;
  final double dash;
  final double gap;

  /// Multiplier on the true angle. Deliberately unrelated to one another, so
  /// the rings never beat together into a readable pattern — that would kill
  /// the smear.
  final double rate;
}

const List<_Streak> _streaks = [
  _Streak(radius: 88, width: 12, opacity: .10, dash: 3, gap: 26, rate: 1.00),
  _Streak(radius: 102, width: 7, opacity: .16, dash: 6, gap: 20, rate: -0.78),
  _Streak(radius: 114, width: 3, opacity: .34, dash: 24, gap: 12, rate: 1.34),
  // The rim line, in the 9px gap outside the seats.
  _Streak(radius: 200, width: 4, opacity: .30, dash: 14, gap: 10, rate: 1.70),
];

class _Seat {
  /// 0 = empty, 1 = someone sitting in it. Everything visible about a seat is
  /// a lerp along this.
  double fill = 0;
  bool occupied = false;
}

class _ReelAnimationState extends State<ReelAnimation>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  final _seats = List.generate(ReelAnimation._seatCount, (_) => _Seat());
  final _random = math.Random();

  // ── strobe engine ────────────────────────────────────────────────────────
  static const double _shutter = 1 / 20; // 20 frames/sec gate
  static const double _step = 360 / ReelAnimation._seatCount; // 45° = one seat
  static const double _sync = _step / _shutter; // deg/s that reads as frozen

  /// The speed program. One smooth function of time — no stages, no switches.
  static const double _sway = 0.040; // ±4% of lock: the slow see-saw
  static const double _seesaw = 7; // s per see-saw cycle
  static const double _over = 1.30; // peak of a surge
  static const double _cycle = 22; // s between surges
  static const double _sharp = 6; // higher = briefer surge, still smooth

  /// Time constants — what keeps anything from happening abruptly. The reel
  /// cannot reach a new speed faster than [_spinTau], and the ring cannot
  /// change apparent direction faster than [_ringTau].
  static const double _spinTau = 1.6;
  static const double _ringTau = 0.40;

  /// Boarding gates in apparent deg/sec, with hysteresis so occupancy does not
  /// chatter while the rate hovers on the boundary.
  static const double _boardBelow = 40;
  static const double _clearAbove = 78;

  double _trueAngle = 0; // where the reel really is (streaks)
  double _ringAngle = 0; // where the ring appears to be (seats, sprockets)
  double _omega = 0; // reel speed, always lagging its target
  double _ringRate = 0; // apparent speed, smoothed
  double _clock = 0;
  Duration _last = Duration.zero;

  /// Gate flicker: a two-state blink on the shutter beat.
  double _gate = 1;

  /// The hub ring's breathing, on its own 2.2s clock.
  double _breathe = 1;

  // ── occupancy ────────────────────────────────────────────────────────────
  /// The room does not run on its own clock. People board only while the
  /// strobe has the ring crawling, and step off the moment it picks up.
  bool _open = false;
  int _target = 0;
  double _nextTick = 0.4;

  static const Duration _transition = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _target = 3 + _random.nextInt(5);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _setOpen(bool next) {
    if (next == _open) return;
    _open = next;
    if (next) _target = 3 + _random.nextInt(5);
  }

  /// Frame-rate independent exponential approach.
  static double _approach(
    double current,
    double target,
    double tau,
    double dt,
  ) => current + (target - current) * (1 - math.exp(-dt / tau));

  /// `sway` is the gentle straddle of sync that people ride; `bump` is a rare,
  /// smooth swell past it. Raising a cosine to a power keeps it near zero most
  /// of the cycle and gives it a soft shoulder either side — no ramp start, no
  /// ramp end, nothing to switch between.
  static double _targetSpeed(double t) {
    final sway = _sway * math.sin(2 * math.pi * t / _seesaw);
    final bump = math.pow(
      0.5 - 0.5 * math.cos(2 * math.pi * t / _cycle),
      _sharp,
    );
    return _sync * (1 + sway + (_over - 1) * bump);
  }

  void _onTick(Duration elapsed) {
    final dt = math.min(
      (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond,
      0.1, // clamp a resumed-from-background jump
    );
    _last = elapsed;
    if (dt <= 0) return;
    _clock += dt;

    // The reel chases its target speed but never snaps to it. This is the
    // inertia, and it is why nothing lurches.
    _omega = _approach(_omega, _targetSpeed(_clock), _spinTau, dt);

    // What a shutter SHOWS is that speed folded into one seat-width: turn 44°
    // between exposures and the ring reads as crawling backwards 1°; turn 46
    // and it creeps forward 1.
    final perExposure = _omega * _shutter;
    var folded = (perExposure % _step + _step) % _step;
    if (folded > _step / 2) folded -= _step; // nearest seat, signed
    final apparent = folded / _shutter;

    // The fold is a sawtooth: cross a half-seat and it flips sign instantly.
    // Physically honest, but it lands as a jolt. Easing toward the folded rate
    // keeps the reversal — it just takes _ringTau to swing through.
    _ringRate = _approach(_ringRate, apparent, _ringTau, dt);

    // Driven continuously rather than stepped once per exposure: the same
    // speed and direction the strobe gives, but it glides instead of
    // teleporting a seat at a time.
    _trueAngle += _omega * dt;
    _ringAngle += _ringRate * dt;

    final speed = _ringRate.abs();
    if (speed < _boardBelow) {
      _setOpen(true);
    } else if (speed > _clearAbove) {
      _setOpen(false);
    }

    if (_clock >= _nextTick) _board();

    // The gate blinks on the shutter beat; the hub breathes on its own.
    _gate = (_clock % 0.45) < 0.225 ? 1.0 : 0.94;
    _breathe = 1 + 0.12 * (0.5 - 0.5 * math.cos(2 * math.pi * _clock / 2.2));

    final rate = dt / (_transition.inMilliseconds / 1000);
    for (final seat in _seats) {
      final target = seat.occupied ? 1.0 : 0.0;
      seat.fill = (seat.fill + (target - seat.fill).sign * rate).clamp(
        0.0,
        1.0,
      );
      if ((target - seat.fill).abs() < rate) seat.fill = target;
    }

    setState(() {});
  }

  void _board() {
    final empty = _seats.where((s) => !s.occupied).toList();
    final guests = _seats.where((s) => s.occupied).toList();

    if (!_open) {
      // Moving too fast to board — everyone steps off.
      if (guests.isNotEmpty) {
        guests[_random.nextInt(guests.length)].occupied = false;
      }
      _nextTick = _clock + 0.17 + _random.nextDouble() * 0.16;
      return;
    }

    if (guests.length < _target && empty.isNotEmpty) {
      empty[_random.nextInt(empty.length)].occupied = true;
    } else if (_random.nextDouble() < 0.45 && guests.isNotEmpty) {
      guests[_random.nextInt(guests.length)].occupied = false;
    } else if (empty.isNotEmpty) {
      empty[_random.nextInt(empty.length)].occupied = true;
    }

    // Deliberately off the shutter beat, so joins and leaves read as their own
    // event instead of syncing into the strobe.
    _nextTick = _clock + 0.48 + _random.nextDouble() * 0.82;
  }

  @override
  Widget build(BuildContext context) {
    // A viewer who asked for less motion gets the reel stopped: no spin, no
    // flicker, no smear — just the room, with the streaks held at a readable
    // opacity.
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return RepaintBoundary(
      child: CustomPaint(
        painter: _ReelPainter(
          trueAngle: still ? 0 : _trueAngle,
          ringAngle: still ? 0 : _ringAngle,
          omega: still ? 0 : _omega,
          gate: still ? 1 : _gate,
          breathe: still ? 1 : _breathe,
          fills: [
            for (final s in _seats) still ? (s.occupied ? 1.0 : 0.0) : s.fill,
          ],
          still: still,
        ),
        size: const Size.square(ReelAnimation._box),
      ),
    );
  }
}

class _ReelPainter extends CustomPainter {
  _ReelPainter({
    required this.trueAngle,
    required this.ringAngle,
    required this.omega,
    required this.gate,
    required this.breathe,
    required this.fills,
    required this.still,
  });

  final double trueAngle;
  final double ringAngle;
  final double omega;
  final double gate;
  final double breathe;
  final List<double> fills;
  final bool still;

  /// The shoulders, in pod-local space: +Y points away from the disc.
  static final Path _body = Path()
    ..moveTo(-8.9, 53)
    ..cubicTo(-38.5, 53, -62.5, 77, -62.5, 106.8)
    ..cubicTo(-62.5, 111.8, -58.5, 115.8, -53.6, 115.8)
    ..lineTo(53.6, 115.8)
    ..cubicTo(58.5, 115.8, 62.5, 111.8, 62.5, 106.8)
    ..cubicTo(62.5, 77, 38.5, 53, 8.9, 53)
    ..close();

  static const double _deg = math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / ReelAnimation._box;
    canvas.save();
    canvas.scale(scale);
    canvas.translate(ReelAnimation._box / 2, ReelAnimation._box / 2);

    // The gate's flutter dims the whole plate, so it is a group opacity rather
    // than something each layer has to know about.
    final flickering = gate < 1;
    if (flickering) {
      canvas.saveLayer(
        Rect.fromCircle(center: Offset.zero, radius: ReelAnimation._box),
        Paint()..color = Color.fromRGBO(0, 0, 0, gate),
      );
    }

    canvas.drawCircle(
      Offset.zero,
      ReelAnimation._discRadius,
      Paint()..color = ReelAnimation._red,
    );
    canvas.drawCircle(
      Offset.zero,
      ReelAnimation._discRadius,
      Paint()
        ..color = ReelAnimation._redEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Speed band, at the TRUE angle: marks fade as they smear, the way a
    // fast-moving edge loses contrast.
    final smear = still
        ? 1.0
        : (1 - 0.55 * (omega / (_ReelAnimationState._sync * 1.30))).clamp(
            0.0,
            1.0,
          );
    for (final streak in _streaks) {
      _dashedRing(
        canvas,
        streak,
        rotation: trueAngle * streak.rate * _deg,
        opacity: still ? 0.18 : streak.opacity * smear,
      );
    }

    // The ring — perforations and people together, at the SAMPLED angle.
    canvas.save();
    canvas.rotate(ringAngle * _deg);

    final perf = Paint()..color = ReelAnimation._ink.withValues(alpha: 0.55);
    for (var p = 0; p < ReelAnimation._seatCount; p++) {
      final a = (p + 0.5) * (360 / ReelAnimation._seatCount) * _deg;
      canvas.drawCircle(
        Offset(
          math.sin(a) * ReelAnimation._orbit,
          math.cos(a) * ReelAnimation._orbit,
        ),
        9,
        perf,
      );
    }

    for (var i = 0; i < fills.length; i++) {
      canvas.save();
      canvas.rotate(i * 2 * math.pi / ReelAnimation._seatCount);
      canvas.translate(0, ReelAnimation._orbit);
      _paintSeat(canvas, fills[i]);
      canvas.restore();
    }
    canvas.restore();

    canvas.drawCircle(Offset.zero, 70, Paint()..color = ReelAnimation._ink);
    canvas.drawCircle(
      Offset.zero,
      60 * breathe,
      Paint()..color = ReelAnimation._cream,
    );

    if (flickering) canvas.restore();
    canvas.restore();
  }

  /// One dashed ring, drawn as arcs. `dash`/`gap` are path lengths, as in SVG,
  /// so they convert to angles through the radius.
  void _dashedRing(
    Canvas canvas,
    _Streak streak, {
    required double rotation,
    required double opacity,
  }) {
    if (opacity <= 0.001) return;
    final r = streak.radius;
    final period = streak.dash + streak.gap;
    if (period <= 0) return;

    final paint = Paint()
      ..color = ReelAnimation._cream.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = streak.width
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: Offset.zero, radius: r);
    final circumference = 2 * math.pi * r;
    final count = (circumference / period).floor();
    final sweep = streak.dash / r;

    for (var i = 0; i < count; i++) {
      canvas.drawArc(rect, rotation + i * period / r, sweep, false, paint);
    }
  }

  /// A seat is a hole punched in the reel with someone sitting in it. The hole
  /// is always there; only the person fades and springs in.
  void _paintSeat(Canvas canvas, double fill) {
    // Shoulders first — the hole is drawn over them, then the head into it.
    if (fill > 0.001) {
      final spring = Curves.easeOutBack.transform(fill.clamp(0.0, 1.0));
      canvas.save();
      // Scaled from the top of its own box, so it grows out of the head rather
      // than out of thin air.
      canvas.translate(0, 53);
      canvas.scale(0.6 + 0.4 * spring, spring);
      canvas.translate(0, -53);
      canvas.drawPath(
        _body,
        Paint()..color = ReelAnimation._cream.withValues(alpha: fill),
      );
      canvas.restore();
    }

    canvas.drawCircle(
      Offset.zero,
      ReelAnimation._hole,
      Paint()..color = ReelAnimation._ink,
    );

    if (fill > 0.001) {
      final spring = Curves.easeOutBack.transform(fill.clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset.zero,
        ReelAnimation._head * (0.3 + 0.7 * spring),
        Paint()..color = ReelAnimation._cream.withValues(alpha: fill),
      );
    }
  }

  @override
  bool shouldRepaint(_ReelPainter old) => true;
}
