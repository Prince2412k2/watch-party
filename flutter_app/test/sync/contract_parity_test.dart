// The Flutter client's half of the cross-language wire contract.
//
// `app/shared/contracts/` holds canonical JSON for the two things the React and
// Flutter clients each implement independently: the sync decision core and the
// socket vocabulary. This file drives the Dart port from those fixtures;
// `app/client/src/sync/contractParity.test.ts` drives the React implementation
// from the same bytes, and `app/server/contract.test.js` pins the fixture to
// the server that defines the protocol.
//
// So: changing one client's understanding of a payload means changing the
// fixture, and changing the fixture fails the other client's suite. That is the
// whole point — without it the two ports can drift silently and every suite
// stays green.
//
// See app/shared/contracts/README.md.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/models/party_state.dart';
import 'package:watchparty/sync/sync_core.dart';

const double _epsilon = 1e-9;

/// `flutter test` runs with the package root as the working directory.
File _repoFile(String relative) {
  final file = File('../$relative');
  if (!file.existsSync()) {
    fail('missing shared contract $relative — expected at ${file.absolute.path}');
  }
  return file;
}

Map<String, dynamic> _readContract(String name) =>
    jsonDecode(_repoFile('app/shared/contracts/$name').readAsStringSync())
        as Map<String, dynamic>;

double _num(Object? value) => (value as num).toDouble();

double? _numOrNull(Object? value) => value == null ? null : (value as num).toDouble();

/// The shape both languages compare through, so the fixture pins semantics
/// rather than either language's way of spelling "field not set".
class _Normalized {
  _Normalized.fromIntent(SyncIntent i)
      : seekTo = i.seekToSec,
        rate = i.rate,
        play = i.play,
        pause = i.pause,
        hardSeek = i.hardSeek,
        pausedSeek = i.pausedSeek,
        drift = i.drift;

  final double? seekTo;
  final double? rate;
  final bool play;
  final bool pause;
  final bool hardSeek;
  final bool pausedSeek;
  final double? drift;
}

void _expectClose(double? actual, double? expected, String what) {
  if (expected == null || actual == null) {
    expect(actual, expected, reason: what);
    return;
  }
  expect((actual - expected).abs() < _epsilon, isTrue,
      reason: '$what: expected $expected, got $actual');
}

/// Every `static const name = 'value';` declared inside [className] in
/// `lib/net/events.dart`. Read from source because the constants are static
/// fields with no runtime enumeration — and because a new constant must not be
/// able to appear without this test seeing it.
Set<String> _declaredEvents(String source, String className) {
  final start = source.indexOf('abstract final class $className {');
  expect(start, isNot(-1), reason: 'no class $className in lib/net/events.dart');
  final end = source.indexOf('\n}', start);
  expect(end, isNot(-1), reason: 'unterminated class $className');
  final body = source.substring(start, end);
  return RegExp(r"static const \w+ = '([^']+)';")
      .allMatches(body)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  final syncContract = _readContract('sync-core.json');
  final eventContract = _readContract('socket-events.json');

  group('sync decision core', () {
    test('the shared contract and sync_core agree on every constant', () {
      final constants = syncContract['constants'] as Map<String, dynamic>;
      // Dart names these in lowerCamelCase; the contract uses the original
      // SCREAMING_SNAKE from syncCore.ts. Mapped explicitly so a rename on
      // either side is a visible edit here rather than a silent skip.
      final declared = <String, num>{
        'TICKS': ticksPerSecond,
        'CONTROL_MS': controlMs,
        'HARD_SEEK_SEC': hardSeekSec,
        'HOST_DRAG_SEEK_SEC': hostDragSeekSec,
        'SOFT_SEC': softSec,
        'SOFT_EXIT_SEC': softExitSec,
        'RATE_GAIN': rateGain,
        'MAX_RATE_ADJ': maxRateAdj,
        'HOLD_TOLERANCE': holdTolerance,
        'HARD_SEEK_COOLDOWN_MS': hardSeekCooldownMs,
      };
      expect(declared.keys.toSet(), constants.keys.toSet(),
          reason: 'the Dart port and the contract disagree on which constants exist');
      for (final entry in constants.entries) {
        _expectClose(_num(declared[entry.key]), _num(entry.value), entry.key);
      }
    });

    for (final raw in syncContract['predictPosition'] as List<dynamic>) {
      final c = raw as Map<String, dynamic>;
      test('predictPosition: ${c['name']}', () {
        final schedule = c['schedule'] == null
            ? null
            : SyncSchedule.fromJson(c['schedule'] as Map<String, dynamic>);
        _expectClose(
          predictPosition(schedule, _num(c['serverNowMs'])),
          _num(c['expect']),
          c['name'] as String,
        );
      });
    }

    for (final raw in syncContract['decideSyncAction'] as List<dynamic>) {
      final c = raw as Map<String, dynamic>;
      test('decideSyncAction: ${c['name']}', () {
        final schedule = c['schedule'] == null
            ? null
            : SyncSchedule.fromJson(c['schedule'] as Map<String, dynamic>);
        final seed = c['correctionState'] as Map<String, dynamic>?;
        final correctionState = seed == null
            ? null
            : (CorrectionState()..correcting = seed['correcting'] as bool);

        final intent = decideSyncAction(
          schedule: schedule,
          serverNowMs: () => _num(c['serverNowMs']),
          clockReady: () => c['clockReady'] as bool,
          currentTime: _num(c['currentTime']),
          paused: c['paused'] as bool,
          isHost: c['isHost'] as bool,
          mode: c['mode'] as String,
          userSeeking: c['userSeeking'] as bool,
          suppressHardSeek: c['suppressHardSeek'] as bool,
          correctionState: correctionState,
        );

        final expected = c['expect'] as Map<String, dynamic>?;
        if (expected == null) {
          expect(intent, isNull, reason: 'expected a no-op tick');
          return;
        }
        expect(intent, isNotNull, reason: 'expected an intent, got a no-op tick');

        final got = _Normalized.fromIntent(intent!);
        _expectClose(got.seekTo, _numOrNull(expected['seekTo']), 'seekTo');
        _expectClose(got.rate, _numOrNull(expected['rate']), 'rate');
        _expectClose(got.drift, _numOrNull(expected['drift']), 'drift');
        expect(got.play, expected['play'], reason: 'play');
        expect(got.pause, expected['pause'], reason: 'pause');
        expect(got.hardSeek, expected['hardSeek'], reason: 'hardSeek');
        expect(got.pausedSeek, expected['pausedSeek'], reason: 'pausedSeek');

        final expectedState = c['expectCorrectionState'] as Map<String, dynamic>?;
        if (expectedState != null) {
          expect(correctionState?.correcting, expectedState['correcting'],
              reason: 'correctionState');
        }
      });
    }
  });

  group('socket vocabulary', () {
    // A client may ignore events it has no use for, so this is containment,
    // not equality: the server test owns the equality direction. What this
    // catches is a name the Flutter client believes in that the server has
    // never heard of — a typo, or a rename applied to only one implementation.
    final source = _repoFile('flutter_app/lib/net/events.dart').readAsStringSync();
    final clientToServer =
        (eventContract['clientToServer'] as List<dynamic>).cast<String>().toSet();
    final serverToClient =
        (eventContract['serverToClient'] as List<dynamic>).cast<String>().toSet();

    test('every ClientEvent exists in the contract as a client→server event', () {
      final declared = _declaredEvents(source, 'ClientEvent');
      expect(declared, isNotEmpty, reason: 'ClientEvent parsed as empty');
      expect(declared.difference(clientToServer).toList()..sort(), isEmpty,
          reason: 'ClientEvent names the server does not handle');
    });

    test('every ServerEvent exists in the contract as a server→client event', () {
      final declared = _declaredEvents(source, 'ServerEvent');
      expect(declared, isNotEmpty, reason: 'ServerEvent parsed as empty');
      expect(declared.difference(serverToClient).toList()..sort(), isEmpty,
          reason: 'ServerEvent names the server never emits');
    });

    test('the Flutter client covers the whole server→client vocabulary', () {
      // Unlike the outbound direction, an unhandled *inbound* event is a real
      // gap: the server will send it and this client will drop it silently.
      final declared = _declaredEvents(source, 'ServerEvent');
      expect(serverToClient.difference(declared).toList()..sort(), isEmpty,
          reason: 'server→client events with no ServerEvent constant');
    });

    test('SyncSchedule decodes exactly the contracted sync:schedule fields', () {
      expect(
        (const SyncSchedule().toJson().keys.toList()..sort()),
        (eventContract['syncScheduleFields'] as List<dynamic>).cast<String>().toList()..sort(),
      );
    });
  });
}
