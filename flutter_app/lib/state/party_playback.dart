// What the room is watching, and who gets to say.
//
// The app plays one title at a time ([nowPlayingProvider]) and a party is an
// ambient room you can carry around it. This file is the join between the two,
// and it holds the rules that make a watch party a watch party rather than two
// people playing the same file:
//
//   * The driver (host, or anyone when collaborative control is on) does not
//     open a title locally. It tells the SERVER, and the `party:state` that
//     comes back opens it here the same way it opens it everywhere else. One
//     path, so the room cannot end up watching two different things.
//   * Everyone follows `party:state.mediaItemId`. A guest is pulled into the
//     host's film wherever they are in the app.
//   * Following NEVER changes how you are watching. If you had the film in a
//     corner and the host switches title, the new title arrives in that corner.
//     Only the first pull-in takes the screen.
//   * A passenger cannot start a film of their own, and cannot close the one
//     they are in. Minimising is always theirs.
//   * While a party title is open, [SyncEngine] drives the local player from
//     the room's schedule. Without it two clients simply play their own copies,
//     which is the state this app shipped in until now.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/party_state.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_impl.dart';
import 'now_playing_provider.dart';
import 'party_provider.dart';
import 'player_provider.dart';
import 'providers.dart';

/// How long the "now playing" card holds the screen while the next title
/// loads behind it. A floor, not a delay: the card stays up past this until
/// playback is actually ready.
const Duration kNowPlayingIntroDwell = Duration(milliseconds: 3500);

/// The title being introduced by the now-playing card, or null.
final nowPlayingIntroProvider = StateProvider<String?>((ref) => null);

/// What the local user may do to the room's playback.
enum PartyRole {
  /// No party. Everything is yours.
  solo,

  /// Host, or a guest in a collaborative room: may choose the title and take
  /// it away again.
  driver,

  /// A guest in a normal room: watches what the driver puts on.
  passenger,
}

/// The outcome of asking to play something.
enum OpenOutcome {
  /// Opened locally (no party).
  opened,

  /// Handed to the room; every member — this one included — opens it when the
  /// server says so.
  sentToRoom,

  /// Refused: a passenger cannot start a title of their own.
  refusedPassenger,

  /// A newer action or party transition replaced this request while it loaded.
  superseded,
}

/// The one sync engine, so a test can put a fake in its place.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngineImpl();
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});

class PartyPlayback {
  PartyPlayback(this._ref, {SyncEngine? engine})
    : _engine = engine ?? _ref.read(syncEngineProvider);

  final Ref _ref;
  final SyncEngine _engine;

  /// The room's title, as last followed. Distinct from what the player holds:
  /// after the party ends the film stays open and stops being the room's.
  String? _followed;
  bool _attached = false;
  String? _attachedPartyId;
  Timer? _introTimer;
  int _openGeneration = 0;

  PartyState? get _party => _ref.read(partyProvider);

  PartyRole get role {
    final party = _party;
    if (party == null) return PartyRole.solo;
    return _ref.read(partyProvider.notifier).isHost ||
            party.collaborativeControl
        ? PartyRole.driver
        : PartyRole.passenger;
  }

  /// Whether the local user's transport gestures mean anything.
  ///
  /// A passenger's play/pause/seek would be undone by the correction loop a
  /// tick later, so the controls are dead rather than dishonest.
  bool get canDrive => role != PartyRole.passenger;

  /// Whether the local user may take the film away.
  ///
  /// A passenger cannot: the film is the room's, and closing it would leave
  /// them in a party watching nothing with no way back to it. Minimising is
  /// unrestricted — see the note at the top of the file.
  bool get canClose => canDrive;
  bool get canManageAudio =>
      _party == null || _ref.read(partyProvider.notifier).isHost;
  Stream<CatchUp> get catchUp => _engine.catchUp;

  /// Tell the room where the driver just scrubbed to.
  ///
  /// The local seek has already happened; this publishes it. Without it the
  /// engine sees the host jump and reads it as drift to correct — the host
  /// would be dragged back to where the room still is.
  void reportSeek(Duration position) {
    if (!_attached || !canDrive) return;
    unawaited(_engine.requestSeek(position));
  }

  /// Chrome must call this INSTEAD OF controller.seek + reportSeek, so the
  /// correction loop is suspended before the native seek starts.
  Future<void> seekTo(Duration position) async {
    if (!canDrive) return;
    if (_attached && _engine is SyncEngineImpl) {
      await _engine.seekTo(position);
    } else {
      await _ref.read(playerControllerProvider).seek(position);
      if (_attached) await _engine.requestSeek(position);
    }
  }

  Future<void> togglePlay() async {
    if (!canDrive) return;
    final player = _ref.read(playerControllerProvider);
    if (!_attached) {
      if (player.isPlayingNow) {
        await player.pause();
      } else {
        await player.play();
      }
      return;
    }
    if (player.isPlayingNow) {
      await _engine.requestPause();
    } else {
      await _engine.requestPlay();
    }
  }

  /// Whether the room's title is what the player currently holds.
  bool get _showingPartyTitle {
    final followed = _followed;
    return followed != null && _ref.read(nowPlayingProvider).itemId == followed;
  }

  String? _pendingSubtitleItemId;
  int? _pendingSubtitleStreamIndex;

  // ── Asking to play something ──────────────────────────────────────────────

  Future<OpenOutcome> requestOpen({
    required String itemId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    final generation = ++_openGeneration;
    final partyId = _party?.id;
    switch (role) {
      case PartyRole.solo:
        _ref
            .read(nowPlayingProvider.notifier)
            .open(
              itemId: itemId,
              audioStreamIndex: audioStreamIndex,
              subtitleStreamIndex: subtitleStreamIndex,
            );
        return OpenOutcome.opened;
      case PartyRole.passenger:
        return OpenOutcome.refusedPassenger;
      case PartyRole.driver:
        _pendingSubtitleItemId = itemId;
        _pendingSubtitleStreamIndex = subtitleStreamIndex;
        final resumePositionTicks = await _resumePositionTicks(itemId);
        if (generation != _openGeneration ||
            _party?.id != partyId ||
            role != PartyRole.driver) {
          return OpenOutcome.superseded;
        }
        await _ref
            .read(partyProvider.notifier)
            .selectMedia(
              mediaItemId: itemId,
              audioStreamIndex: audioStreamIndex,
              resumePositionTicks: resumePositionTicks,
            );
        return OpenOutcome.sentToRoom;
    }
  }

  Future<void> selectAudioStream(int? index) async {
    if (_party == null || !canManageAudio) return;
    await _ref.read(partyProvider.notifier).setAudioStream(index);
  }

  Future<int?> _resumePositionTicks(String itemId) async {
    try {
      final item = await _ref.read(apiClientProvider).item(itemId);
      final ticks = item.userData?.playbackPositionTicks ?? 0;
      return ticks > 0 ? ticks : null;
    } catch (_) {
      return null;
    }
  }

  /// Close: for the room when a party is running, for this app otherwise.
  Future<void> close() async {
    if (!canClose) return;
    if (_party != null && _showingPartyTitle) {
      // The server clears the selection and tells everyone; the follow path
      // below is what actually closes the player here, exactly as it does for
      // the guests.
      await _ref.read(partyProvider.notifier).backToLobby();
      return;
    }
    await _ref.read(nowPlayingProvider.notifier).close();
  }

  // ── Following the room ────────────────────────────────────────────────────

  void onParty(PartyState? previous, PartyState? next) {
    if (previous?.id != next?.id) _openGeneration++;
    _followMedia(next);
    _syncEngineLifecycle();
  }

  void onNowPlaying(NowPlaying? previous, NowPlaying next) =>
      _syncEngineLifecycle();

  void _followMedia(PartyState? party) {
    final wanted = party?.mediaItemId;
    final nowPlaying = _ref.read(nowPlayingProvider);
    final mediaChanged = wanted != _followed;
    final hasPendingSubtitle = wanted != null && _pendingSubtitleItemId == wanted;
    final unchanged =
        !mediaChanged &&
        !hasPendingSubtitle &&
        nowPlaying.mediaSourceId == party?.mediaSourceId &&
        nowPlaying.audioStreamIndex == party?.playback?.selectedAudioIndex;
    if (unchanged) return;

    // Left the room, or the driver put the film away: whoever is left holding
    // it stops. A film the party took away is not yours to keep watching.
    if (wanted == null) {
      final wasFollowing = _showingPartyTitle;
      _followed = null;
      if (wasFollowing && party != null) {
        unawaited(_ref.read(nowPlayingProvider.notifier).close());
      }
      return;
    }

    _followed = wanted;

    // The heart of "keep the guest's state": already watching something means
    // you are already watching it SOMEWHERE, and that is where the new title
    // appears. Only someone with nothing open gets taken over.
    final presentation = nowPlaying.isOpen
        ? nowPlaying.presentation
        : PlayerPresentation.expanded;

    if (mediaChanged) _showIntro(wanted);
    final pendingSubtitle = hasPendingSubtitle
        ? _pendingSubtitleStreamIndex
        : null;
    if (hasPendingSubtitle) {
      _pendingSubtitleItemId = null;
      _pendingSubtitleStreamIndex = null;
    }
    _ref
        .read(nowPlayingProvider.notifier)
        .open(
          itemId: wanted,
          mediaSourceId: party?.mediaSourceId,
          audioStreamIndex: party?.playback?.selectedAudioIndex,
          // A driver's pre-play choice is handed directly to this client. It
          // never enters party state; everyone else starts independently.
          subtitleStreamIndex: hasPendingSubtitle
              ? pendingSubtitle
              : (mediaChanged ? null : nowPlaying.subtitleStreamIndex),
          presentation: presentation,
        );
  }

  void _showIntro(String itemId) {
    _introTimer?.cancel();
    _ref.read(nowPlayingIntroProvider.notifier).state = itemId;
    _introTimer = Timer(kNowPlayingIntroDwell, () {
      if (_ref.read(nowPlayingIntroProvider) == itemId) {
        _ref.read(nowPlayingIntroProvider.notifier).state = null;
      }
    });
  }

  // ── The sync engine ───────────────────────────────────────────────────────

  void _syncEngineLifecycle() {
    final party = _party;
    final wanted =
        party != null &&
        _showingPartyTitle &&
        _ref.read(nowPlayingProvider).isOpen;

    if (!wanted) {
      if (_attached) {
        _attached = false;
        _attachedPartyId = null;
        unawaited(_engine.detach());
      }
      return;
    }

    // Role can move under a running party — collaborative control toggling, the
    // host handing over — so this is refreshed on every party change, not just
    // at attach.
    final driver = role == PartyRole.driver;
    _engine.canControl = driver;
    if (_engine case final SyncEngineImpl impl) {
      impl.isHost = _ref.read(partyProvider.notifier).isHost;
      impl.syncMode = party.syncMode;
      impl.downloadedChunks = () {
        final itemId = party.mediaItemId;
        if (itemId == null) return 0;
        return _ref
            .read(mediaCacheProxyProvider)
            .cachedSpansFor(itemId)
            .value
            .length;
      };
    }
    if (_attached && _attachedPartyId == party.id) {
      if (_engine case final SyncEngineImpl impl) {
        impl.acceptSchedule(party.schedule);
      }
      return;
    }

    _attached = true;
    _attachedPartyId = party.id;
    unawaited(
      _engine
          .attach(
            player: _ref.read(playerControllerProvider),
            socket: _ref.read(socketClientProvider),
            partyId: party.id,
            canControl: driver,
          )
          .then((_) {
            if (_attached &&
                _attachedPartyId == party.id &&
                _party?.id == party.id) {
              if (_engine case final SyncEngineImpl impl) {
                impl.acceptSchedule(_party!.schedule);
              }
            }
          }),
    );
  }

  void dispose() {
    _introTimer?.cancel();
    if (_attached) unawaited(_engine.detach());
  }
}

/// Kept alive by [PlayerHost], which is mounted for the life of the app — the
/// rules here have to be running before anyone opens anything.
final partyPlaybackProvider = Provider<PartyPlayback>((ref) {
  final playback = PartyPlayback(ref);
  ref.listen<PartyState?>(
    partyProvider,
    playback.onParty,
    fireImmediately: true,
  );
  ref.listen<NowPlaying>(nowPlayingProvider, playback.onNowPlaying);
  ref.onDispose(playback.dispose);
  return playback;
});
