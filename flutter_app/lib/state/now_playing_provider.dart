// What is playing, and how it is being shown.
//
// Playback used to be a *screen*: `DetailScreen` and `PartyScreen` each mounted
// their own `PlayerView` inside a full-window Scaffold, and `dispose()` paused
// and rewound. So Back did not minimise playback, it ended it.
//
// This provider is the fix in one sentence: what is playing is STATE, and the
// presentation is a property of that state rather than a route. Nothing here
// touches the widget tree — `PlayerHost` renders whatever this says, once,
// above the router.
//
// The invariant worth protecting: **only `close()` stops playback.** Minimising,
// expanding, navigating and rebuilding must never reach the controller. Every
// bug this file exists to prevent is a variation of something else calling
// pause().

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/player_controller.dart';
import 'player_provider.dart';

/// How the single player instance is being shown right now.
enum PlayerPresentation {
  /// Nothing is playing. The host renders nothing at all.
  hidden,

  /// A draggable, resizable tile over whatever screen you are on — the same
  /// treatment a person's camera gets.
  floating,

  /// Full-window. The only thing in the app that takes the screen over.
  expanded,
}

/// The title currently open in the shared player, and how it is presented.
class NowPlaying {
  const NowPlaying({
    this.itemId,
    this.mediaSourceId,
    this.title,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.presentation = PlayerPresentation.hidden,
    this.revision = 0,
  });

  final String? itemId;
  final String? mediaSourceId;
  final String? title;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final PlayerPresentation presentation;

  /// Changes whenever the requested source or track selection changes, even if
  /// the library item id stays the same.
  final int revision;

  bool get isOpen =>
      itemId != null && presentation != PlayerPresentation.hidden;
  bool get isExpanded => presentation == PlayerPresentation.expanded;
  bool get isFloating => presentation == PlayerPresentation.floating;

  NowPlaying copyWith({
    String? itemId,
    String? mediaSourceId,
    String? title,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    PlayerPresentation? presentation,
    int? revision,
  }) => NowPlaying(
    itemId: itemId ?? this.itemId,
    mediaSourceId: mediaSourceId ?? this.mediaSourceId,
    title: title ?? this.title,
    audioStreamIndex: audioStreamIndex ?? this.audioStreamIndex,
    subtitleStreamIndex: subtitleStreamIndex ?? this.subtitleStreamIndex,
    presentation: presentation ?? this.presentation,
    revision: revision ?? this.revision,
  );
}

class NowPlayingNotifier extends StateNotifier<NowPlaying> {
  NowPlayingNotifier(this._ref) : super(const NowPlaying());

  final Ref _ref;

  /// Read on demand, never in the constructor.
  ///
  /// `playerControllerProvider` builds a real media_kit controller, and this
  /// provider is watched by the host on every frame of the app — including
  /// before anything has ever been played. Watching it eagerly initialised
  /// libmpv at launch for every user, and threw outright anywhere media_kit had
  /// not been set up. `close()` is the only member that needs it.
  PlayerController get _player => _ref.read(playerControllerProvider);

  /// Open a title, full-window by default.
  ///
  void open({
    required String itemId,
    String? mediaSourceId,
    String? title,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    PlayerPresentation presentation = PlayerPresentation.expanded,
  }) {
    final samePlayback =
        state.itemId == itemId &&
        state.mediaSourceId == mediaSourceId &&
        state.title == title &&
        state.audioStreamIndex == audioStreamIndex &&
        state.subtitleStreamIndex == subtitleStreamIndex;
    if (samePlayback) {
      state = state.copyWith(presentation: presentation);
      return;
    }
    state = NowPlaying(
      itemId: itemId,
      mediaSourceId: mediaSourceId,
      title: title,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      presentation: presentation,
      revision: state.revision + 1,
    );
  }

  /// Back / Escape out of full-window. Deliberately does NOT touch the
  /// controller — this is the whole point of the file.
  void minimise() {
    if (!state.isOpen) return;
    state = state.copyWith(presentation: PlayerPresentation.floating);
  }

  /// Back to full-window from the floating tile.
  void expand() {
    if (!state.isOpen) return;
    state = state.copyWith(presentation: PlayerPresentation.expanded);
  }

  /// Stop. The ONLY path in the app that pauses and rewinds.
  Future<void> close() async {
    if (state.presentation == PlayerPresentation.hidden &&
        state.itemId == null) {
      return;
    }
    state = NowPlaying(revision: state.revision + 1);
    // Ordered: state first, so the host unmounts the surface before the
    // controller work lands. Guarded independently for the same reason
    // `_leaveLocal` guards its steps — one failure must not skip the rest.
    await _ref.read(playbackOperationsProvider).replace((isSuperseded) async {
      try {
        await _player.pause();
      } catch (_) {}
      if (isSuperseded()) return;
      try {
        await _player.seek(Duration.zero);
      } catch (_) {}
    });
  }
}

/// Serializes every mutation of the app-wide player controller. A newer
/// operation invalidates queued work, while work already inside a native open
/// is allowed to finish before the current owner settles the controller.
class PlaybackOperations {
  int _generation = 0;
  Future<void> _tail = Future<void>.value();

  Future<T?> replace<T>(Future<T> Function(bool Function()) operation) {
    final generation = ++_generation;
    return _enqueue(generation, operation);
  }

  Future<T?> _enqueue<T>(
    int generation,
    Future<T> Function(bool Function()) operation,
  ) {
    final completer = Completer<T?>();
    final queued = _tail.then((_) async {
      if (generation != _generation) {
        completer.complete(null);
        return;
      }
      try {
        final value = await operation(() => generation != _generation);
        completer.complete(generation == _generation ? value : null);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _tail = queued.catchError((_) {});
    return completer.future;
  }
}

final playbackOperationsProvider = Provider<PlaybackOperations>(
  (ref) => PlaybackOperations(),
);

/// Whether the expanded player's chrome is currently on screen.
///
/// Published by the player so that OTHER root-mounted chrome can hide with it.
/// The popcorn is the reason this exists: it sits above the player, so during a
/// film it was the one thing that never faded — a tray button parked on top of
/// the transport bar while everything around it dimmed away.
final playerChromeVisibleProvider = StateProvider<bool>((ref) => true);

final nowPlayingProvider =
    StateNotifierProvider<NowPlayingNotifier, NowPlaying>(
      NowPlayingNotifier.new,
    );
