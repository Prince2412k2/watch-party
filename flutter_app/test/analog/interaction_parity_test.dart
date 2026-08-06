// The Flutter client's half of the analog interaction contract.
//
// app/shared/design/interaction.json holds the canonical behaviour cases for
// the interaction cores that #66/#67 require to behave identically in both
// clients. This file drives the Dart ports from those cases;
// app/client/src/analog/interactionParity.test.ts drives the TypeScript
// implementations from the same bytes.
//
// Nothing in the build links the two ports together, so without this the stage
// could step one item per flick in React and three in Flutter, and both suites
// would stay green. See app/shared/design/README.md.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/browse_core.dart';
import 'package:watchparty/analog/player_core.dart';
import 'package:watchparty/ui/analog_tokens.dart';

/// `flutter test` runs with the package root as the working directory.
Map<String, dynamic> _fixture() {
  final file = File('../app/shared/design/interaction.json');
  if (!file.existsSync()) {
    fail('missing interaction fixture — expected at ${file.absolute.path}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

final Map<String, dynamic> fixture = _fixture();

List<Map<String, dynamic>> _cases(String section) =>
    (fixture[section]['cases'] as List).cast<Map<String, dynamic>>();

void main() {
  test('stepped scroll matches the shared interaction cases', () {
    final raw = fixture['steppedScroll']['config'] as Map<String, dynamic>;
    final config = SteppedScrollConfig(
      stepThresholdPx: (raw['stepThresholdPx'] as num).toDouble(),
      gestureIdleMs: (raw['gestureIdleMs'] as num).toDouble(),
      stepCooldownMs: (raw['stepCooldownMs'] as num).toDouble(),
      inertiaFloorPx: (raw['inertiaFloorPx'] as num).toDouble(),
    );

    for (final testCase in _cases('steppedScroll')) {
      final state = SteppedScrollState();
      final events = (testCase['events'] as List).cast<Map<String, dynamic>>();
      for (var index = 0; index < events.length; index++) {
        final event = events[index];
        final steps = steppedScroll(
          state,
          (event['deltaPx'] as num).toDouble(),
          (event['atMs'] as num).toDouble(),
          config,
        );
        expect(
          steps,
          event['expect'],
          reason: '${testCase['name']}: event $index '
              '(delta ${event['deltaPx']} at ${event['atMs']}ms)',
        );
      }
    }
  });

  test('focus restoration matches the shared interaction cases', () {
    for (final testCase in _cases('focusRestore')) {
      final memory = <String, FocusPosition>{
        for (final entry in (testCase['memory'] as Map).entries)
          entry.key as String: FocusPosition(
            shelfId: entry.value['shelfId'] as String,
            itemId: entry.value['itemId'] as String,
          ),
      };
      final shelves = (testCase['shelves'] as List)
          .map((shelf) => ShelfSnapshot(
                shelfId: shelf['shelfId'] as String,
                itemIds: (shelf['itemIds'] as List).cast<String>(),
              ))
          .toList();

      final result = restoreFocus(
        memory,
        testCase['surfaceId'] as String,
        shelves,
        testCase['rememberedIndex'] as int,
      );

      final expected = testCase['expect'] as Map<String, dynamic>;
      expect(result.kind.wireName, expected['kind'], reason: '${testCase['name']}: kind');

      final expectedPosition = expected['position'] as Map<String, dynamic>?;
      if (expectedPosition == null) {
        expect(result.position, isNull, reason: '${testCase['name']}: position');
      } else {
        expect(
          result.position,
          FocusPosition(
            shelfId: expectedPosition['shelfId'] as String,
            itemId: expectedPosition['itemId'] as String,
          ),
          reason: '${testCase['name']}: position',
        );
      }
    }
  });

  test('season artwork fallback matches the shared interaction cases', () {
    for (final testCase in _cases('seasonArtwork')) {
      final raw = testCase['input'] as Map<String, dynamic>;
      final artwork = resolveSeasonArtwork(SeasonArtworkInput(
        seasonId: raw['seasonId'] as String,
        seasonNumber: raw['seasonNumber'] as int?,
        seasonImageTag: raw['seasonImageTag'] as String?,
        seriesId: raw['seriesId'] as String,
        seriesImageTag: raw['seriesImageTag'] as String?,
        failedIds: (raw['failedIds'] as List).cast<String>(),
      ));

      final expected = testCase['expect'] as Map<String, dynamic>;
      final name = testCase['name'];
      expect(artwork.kind.name, expected['kind'], reason: '$name: kind');
      expect(artwork.itemId, expected['itemId'], reason: '$name: itemId');
      expect(artwork.imageTag, expected['imageTag'], reason: '$name: imageTag');
      expect(artwork.label, expected['label'], reason: '$name: label');
    }
  });

  test('the chat toast queue matches the shared interaction cases', () {
    for (final testCase in _cases('toastQueue')) {
      var state = const ToastQueueState();

      for (final op in (testCase['ops'] as List).cast<Map<String, dynamic>>()) {
        switch (op['op']) {
          case 'push':
            state = pushToast(
              state,
              ToastMessage(
                id: op['id'] as String,
                sender: op['sender'] as String,
                preview: op['preview'] as String,
                receivedAtMs: op['atMs'] as int,
              ),
            );
          case 'expire':
            state = expireToasts(state, op['atMs'] as int);
          case 'chat':
            state = setChatOpen(state, op['open'] as bool);
          case 'view':
            final view = toastView(state);
            expect(
              view.toasts.map((toast) => toast.id).toList(),
              (op['toasts'] as List).cast<String>(),
              reason: '${testCase['name']}: visible toasts',
            );
            expect(
              view.collapsedCount,
              op['collapsedCount'],
              reason: '${testCase['name']}: collapsed count',
            );
          default:
            fail('${testCase['name']}: unknown toastQueue op "${op['op']}"');
        }
      }
    }
  });

  test('control auto-hide matches the shared interaction cases', () {
    for (final testCase in _cases('autoHide')) {
      var state = AutoHideState.initial(
        atMs: testCase['startAtMs'] as int,
        playing: true,
      );

      for (final op in (testCase['ops'] as List).cast<Map<String, dynamic>>()) {
        switch (op['op']) {
          case 'input':
            state = noteInput(
              state,
              PlayerInputKind.values.byName(op['kind'] as String),
              op['atMs'] as int,
            );
          case 'hold':
            state = holdControls(state, op['reason'] as String);
          case 'release':
            state = releaseControls(state, op['reason'] as String, op['atMs'] as int);
          case 'playing':
            state = setPlaying(state, op['value'] as bool, op['atMs'] as int);
          case 'tick':
            state = tickAutoHide(state, op['atMs'] as int);
            expect(
              state.visible,
              op['expectVisible'],
              reason: '${testCase['name']}: visible at ${op['atMs']}ms',
            );
          default:
            fail('${testCase['name']}: unknown autoHide op "${op['op']}"');
        }
      }
    }
  });

  test('the chat shortcut guard matches the shared interaction cases', () {
    for (final testCase in _cases('chatShortcut')) {
      final raw = testCase['context'] as Map<String, dynamic>;
      expect(
        shouldToggleChat(ChatShortcutContext(
          ctrlOrMeta: raw['ctrlOrMeta'] as bool,
          key: raw['key'] as String,
          editable: raw['editable'] as bool,
          hasSelection: raw['hasSelection'] as bool,
        )),
        testCase['expect'],
        reason: testCase['name'] as String,
      );
    }
  });

  test('the fixed-cursor rail window matches the shared interaction cases', () {
    for (final testCase in _cases('railWindow')) {
      final raw = testCase['input'] as Map<String, dynamic>;
      final window = railWindow(RailWindowInput(
        total: raw['total'] as int,
        offset: raw['offset'] as int,
        slots: raw['slots'] as int,
        lookahead: raw['lookahead'] as int,
        behind: raw['behind'] as int,
      ));
      final expected = testCase['expect'] as Map<String, dynamic>;
      expect(window.visible, (expected['visible'] as List).cast<int>(),
          reason: '${testCase['name']}: visible');
      expect(window.prefetch, (expected['prefetch'] as List).cast<int>(),
          reason: '${testCase['name']}: prefetch');
    }
  });

  test('the toast and auto-hide timings come from the design tokens', () {
    // The fixture hard-codes 4000ms / 3000ms / a stack of three. Those numbers
    // are design decisions that live in analog-tokens.json, so pin them
    // together — otherwise changing a token silently invalidates every timing
    // case above. The React suite asserts the same three values.
    expect(AnalogTiming.toastLifetimeMs.inMilliseconds, 4000);
    expect(AnalogTiming.chromeAutoHideMs.inMilliseconds, 3000);
    expect(AnalogTiming.toastMaxStack, 3);
  });
}
