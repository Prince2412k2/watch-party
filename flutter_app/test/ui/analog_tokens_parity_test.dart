// The Flutter half of the design-token contract.
//
// app/shared/design/analog-tokens.json is the canonical source; the Dart file
// under test is generated from it by app/shared/design/generate.mjs. The React
// suite re-runs that generator and byte-compares all three outputs, which
// catches a stale or hand-edited file.
//
// What a byte-compare cannot catch is a wrong *transform*: the generator
// consistently emitting `Color(0xF4EFE6A3)` instead of `Color(0xA3F4EFE6)`
// would regenerate identically forever and be wrong in both places. Dart cannot
// run the Node generator, so this file re-derives the values from the JSON
// independently and asserts the constants match.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/ui/analog_tokens.dart';

/// `flutter test` runs with the package root as the working directory.
Map<String, dynamic> _tokens() {
  final file = File('../app/shared/design/analog-tokens.json');
  if (!file.existsSync()) {
    fail('missing design tokens — expected at ${file.absolute.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

final Map<String, dynamic> tokens = _tokens();

Map<String, dynamic> _group(String name) => tokens[name] as Map<String, dynamic>;

/// `#RRGGBB` / `#RRGGBBAA` -> the ARGB int Dart's [Color] takes.
int _argb(String hex) {
  final body = hex.substring(1);
  final rgb = int.parse(body.substring(0, 6), radix: 16);
  final alpha = body.length == 8 ? int.parse(body.substring(6, 8), radix: 16) : 0xFF;
  return (alpha << 24) | rgb;
}

double _double(Object? value) => (value as num).toDouble();

void main() {
  test('colours carry the JSON alpha into Dart ARGB order', () {
    final colors = _group('color');
    final actual = <String, Color>{
      'stageVoid': AnalogColor.stageVoid,
      'stageGround': AnalogColor.stageGround,
      'stageSurface': AnalogColor.stageSurface,
      'stageSurface2': AnalogColor.stageSurface2,
      'stageSurface3': AnalogColor.stageSurface3,
      'ink': AnalogColor.ink,
      'inkDim': AnalogColor.inkDim,
      'inkFaint': AnalogColor.inkFaint,
      'line': AnalogColor.line,
      'lineStrong': AnalogColor.lineStrong,
      'edgeLight': AnalogColor.edgeLight,
      'edgeShade': AnalogColor.edgeShade,
      'shadowCast': AnalogColor.shadowCast,
      'shadowCastStrong': AnalogColor.shadowCastStrong,
      'backdropScrim': AnalogColor.backdropScrim,
      'backdropVignette': AnalogColor.backdropVignette,
      'accent': AnalogColor.accent,
      'onAccent': AnalogColor.onAccent,
      'statusDanger': AnalogColor.statusDanger,
      'statusSuccess': AnalogColor.statusSuccess,
      'statusLive': AnalogColor.statusLive,
      'statusPartyLive': AnalogColor.statusPartyLive,
    };

    // Every colour in the JSON must be represented — a token added to the JSON
    // and never wired up here would go unchecked.
    final declared = colors.keys.where((key) => !key.startsWith(r'$')).toSet();
    expect(actual.keys.toSet(), declared, reason: 'colour coverage');

    for (final entry in actual.entries) {
      expect(
        entry.value.toARGB32(),
        _argb(colors[entry.key] as String),
        reason: '${entry.key} (${colors[entry.key]})',
      );
    }
  });

  test('durations are emitted in milliseconds', () {
    expect(AnalogMotion.focusStepMs.inMilliseconds, _group('motion')['focusStepMs']);
    expect(AnalogMotion.backdropCrossMs.inMilliseconds, _group('motion')['backdropCrossMs']);
    expect(AnalogMotion.chromeFadeMs.inMilliseconds, _group('motion')['chromeFadeMs']);
    expect(AnalogMotion.detentMs.inMilliseconds, _group('motion')['detentMs']);
    expect(AnalogMotion.drawerMs.inMilliseconds, _group('motion')['drawerMs']);
    expect(AnalogTiming.chromeAutoHideMs.inMilliseconds, _group('timing')['chromeAutoHideMs']);
    expect(AnalogTiming.toastLifetimeMs.inMilliseconds, _group('timing')['toastLifetimeMs']);
  });

  test('easing curves are the same four control points as the web', () {
    // This is the one that makes "the same motion in both clients" literal
    // rather than aspirational: CSS gets cubic-bezier(a,b,c,d) and Flutter gets
    // Cubic(a,b,c,d) from the same four numbers.
    final motion = _group('motion');
    final curves = <String, Cubic>{
      'focusStepEase': AnalogMotion.focusStepEase,
      'backdropCrossEase': AnalogMotion.backdropCrossEase,
      'chromeFadeEase': AnalogMotion.chromeFadeEase,
      'detentEase': AnalogMotion.detentEase,
      'drawerEase': AnalogMotion.drawerEase,
      'enterEase': AnalogMotion.enterEase,
      'exitEase': AnalogMotion.exitEase,
    };

    final declared = motion.keys.where((key) => key.endsWith('Ease')).toSet();
    expect(curves.keys.toSet(), declared, reason: 'easing coverage');

    for (final entry in curves.entries) {
      final points = (motion[entry.key] as List).map(_double).toList();
      expect(
        [entry.value.a, entry.value.b, entry.value.c, entry.value.d],
        points,
        reason: entry.key,
      );
    }
  });

  test('lengths and ratios survive the transform', () {
    expect(AnalogPoster.radiusPx, _double(_group('poster')['radiusPx']));
    expect(AnalogPoster.framePx, _double(_group('poster')['framePx']));
    expect(AnalogPoster.gapPx, _double(_group('poster')['gapPx']));
    expect(AnalogSelection.focusScale, _double(_group('selection')['focusScale']));
    expect(AnalogSelection.focusLiftPx, _double(_group('selection')['focusLiftPx']));
    expect(AnalogHairline.idlePx, _double(_group('hairline')['idlePx']));
    expect(AnalogHairline.activePx, _double(_group('hairline')['activePx']));
    expect(AnalogHairline.hitPx, _double(_group('hairline')['hitPx']));
    expect(AnalogGrain.opacityPct, _double(_group('grain')['opacityPct']));
  });

  test('counts stay integers rather than becoming doubles', () {
    expect(AnalogTiming.toastMaxStack, isA<int>());
    expect(AnalogTiming.toastMaxStack, _group('timing')['toastMaxStack']);
    expect(AnalogPoster.aspectW, isA<int>());
    expect(AnalogPoster.aspectH, isA<int>());
    expect(AnalogZ.backdrop, isA<int>());
    expect(AnalogZ.toast, _group('z')['toast']);
  });

  test('poster artwork is square at every size', () {
    // "Every poster has square, unrounded artwork, including skeletons,
    // placeholders, seasons, and selected states." The React suite pins the
    // same value; both clients fail together if the token is ever softened.
    expect(AnalogPoster.radiusPx, 0.0);
  });
}
