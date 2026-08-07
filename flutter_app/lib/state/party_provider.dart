import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../analog/chrome/analog_toast.dart';
import '../app/router.dart';
import '../models/models.dart';
import '../net/events.dart';
import '../net/socket_client.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_impl.dart';
import 'chat_provider.dart';
import 'livekit_provider.dart';
import 'player_provider.dart';
import 'providers.dart';
import 'shared_browser_provider.dart';

/// Watch-party lifecycle over the socket (PLAN §3.8, E5.2). Owns
/// create/join/approve/reject/kick/end/transferHost/setCollaborative/
/// setSyncMode/selectMedia/backToLobby, the participant roster, host
/// detection, and wiring the shared [PlayerController] + [SyncEngineImpl]
/// (setting the real `isHost`, which `attach()` alone can't carry — see the
/// friction note on `SyncEngineImpl._isHost`).
class PartyNotifier extends StateNotifier<PartyState?> {
  PartyNotifier(this._ref) : super(null);

  final Ref _ref;
  final List<void Function()> _unsubs = [];

  /// The engine this notifier attached, held so [dispose] can detach it without
  /// reading a provider off a container that is already tearing down.
  SyncEngine? _attachedEngine;

  StreamSubscription<bool>? _connectionSubscription;
  bool _subscribed = false;
  bool _recoveringConnection = false;
  String? _pendingPartyId;

  SocketClient get _socket => _ref.read(socketClientProvider);
  String? get _myUserId => _ref.read(currentUserIdProvider);

  /// True once a session snapshot has been applied for a party this client is
  /// part of (lobby or watching).
  bool get inParty => state != null;

  bool get isHost =>
      state != null && _myUserId != null && state!.hostId == _myUserId;

  bool get canControl => isHost || (state?.collaborativeControl ?? false);

  PlaybackInfo? _playback;
  SubtitlePreferences _subtitlePreferences = SubtitlePreferences.defaults;

  PlaybackInfo? get playback => _playback;
  SubtitlePreferences get subtitlePreferences => _subtitlePreferences;

  // ── Direct state mutations (kept for tests / callers that already have a
  // ready-made snapshot) ────────────────────────────────────────────────────
  void setState(PartyState? party) {
    state = party;
    _syncRoleToEngine();
  }

  void applySchedule(SyncSchedule schedule) {
    final s = state;
    if (s != null) state = s.copyWith(schedule: schedule);
  }

  void upsertParticipant(Participant p) {
    final s = state;
    if (s == null) return;
    final list = [...s.participants.where((e) => e.userId != p.userId), p];
    state = s.copyWith(participants: list);
  }

  void removeParticipant(String userId) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(
      participants: s.participants.where((e) => e.userId != userId).toList(),
    );
  }

  void clear() {
    state = null;
    _pendingPartyId = null;
    _playback = null;
    _subtitlePreferences = SubtitlePreferences.defaults;
    _ref.read(partyWaitingProvider.notifier).clear();
    _ref.read(sharedBrowserProvider.notifier).clear();
    // There is no party surface left to be minimized away from, so the shell's
    // auto-open must not stay latched shut for the next session.
    _ref.read(partyMinimizedProvider.notifier).restore();
  }

  // ── Socket subscription (idempotent) ─────────────────────────────────────
  Future<void> _ensureConnected() async {
    if (!_socket.isConnected) await _socket.connect();
    if (!_subscribed) _subscribe();
  }

  void _subscribe() {
    _subscribed = true;
    final socket = _socket;
    _connectionSubscription = socket.connectionState.listen((connected) {
      if (connected && (state != null || _pendingPartyId != null)) {
        unawaited(_recoverAfterReconnect());
      }
    });
    _unsubs.add(
      socket.on(ServerEvent.partyState, (data) {
        if (data is Map) _applySession(Map<String, dynamic>.from(data));
      }),
    );
    _unsubs.add(
      socket.on(ServerEvent.partyWaiting, (data) {
        if (data is! Map) return;
        final json = Map<String, dynamic>.from(data);
        final userId = json['userId']?.toString();
        if (userId == null) return;
        final name = json['name']?.toString() ?? userId;
        _ref
            .read(partyWaitingProvider.notifier)
            .add(Participant(userId: userId, name: name));
        _toast('$name wants to join', level: 'warning');
      }),
    );
    _unsubs.add(
      socket.on(ServerEvent.partyApproved, (data) {
        _pendingPartyId = null;
        if (data is Map && data['session'] is Map) {
          _applySession(Map<String, dynamic>.from(data['session'] as Map));
        }
        _postJoinSetup();
      }),
    );
    _unsubs.add(
      socket.on(ServerEvent.partyRejected, (_) {
        _toast('The host declined your request');
        _leaveLocal();
      }),
    );
    _unsubs.add(
      socket.on(ServerEvent.partyKicked, (data) {
        final userId = (data is Map) ? data['userId']?.toString() : null;
        if (userId != null && userId == _myUserId) {
          _toast('You were removed from the party');
          _leaveLocal();
        } else if (userId != null) {
          removeParticipant(userId);
        }
      }),
    );
    _unsubs.add(
      socket.on(ServerEvent.partyEnded, (_) {
        _toast('The host ended the party');
        _leaveLocal();
      }),
    );
    _unsubs.add(
      socket.on(ServerEvent.hostChanged, (data) {
        final hostId = (data is Map) ? data['hostId']?.toString() : null;
        final s = state;
        if (s == null || hostId == null) return;
        state = s.copyWith(hostId: hostId);
        _syncRoleToEngine();
        if (hostId == _myUserId) {
          _toast('You are now the host', level: 'success');
        }
      }),
    );
    _unsubs.add(
      socket.on(ServerEvent.userJoined, (data) {
        if (data is! Map) return;
        final userId = data['userId']?.toString();
        if (userId == null) return;
        final name = data['name']?.toString() ?? userId;
        upsertParticipant(Participant(userId: userId, name: name));
        _toast('$name joined');
      }),
    );
    _unsubs.add(
      socket.on(ServerEvent.userLeft, (data) {
        if (data is! Map) return;
        final userId = data['userId']?.toString();
        if (userId == null) return;
        final name = data['name']?.toString() ?? _participantName(userId);
        removeParticipant(userId);
        _toast('$name left');
      }),
    );
    _unsubs.add(
      // The shared browser failed. Advisory only: the party — playback, cameras,
      // chat — is unaffected, and the server has already returned it to the lobby.
      socket.on(ServerEvent.browserError, (data) {
        if (data is! Map) return;
        final message = data['message']?.toString();
        if (message == null || message.isEmpty) return;
        _toast(message, level: 'error');
      }),
    );
  }

  void _unsubscribe() {
    for (final u in _unsubs) {
      u();
    }
    _unsubs.clear();
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _subscribed = false;
  }

  Future<void> _recoverAfterReconnect() async {
    if (_recoveringConnection) return;
    _recoveringConnection = true;
    try {
      final pendingPartyId = _pendingPartyId;
      if (pendingPartyId != null) {
        final resp = await _socket
            .emitWithAck(ClientEvent.partyJoin, {'partyId': pendingPartyId})
            .timeout(const Duration(seconds: 5));
        if (resp is Map &&
            resp['status'] == 'joined' &&
            resp['session'] is Map) {
          _pendingPartyId = null;
          _applySession(Map<String, dynamic>.from(resp['session'] as Map));
          await _postJoinSetup();
        }
        return;
      }

      final resp = await _socket
          .emitWithAck(ClientEvent.partyResume)
          .timeout(const Duration(seconds: 5));
      if (resp is Map && resp['session'] is Map) {
        _applySession(Map<String, dynamic>.from(resp['session'] as Map));
      } else {
        await _leaveLocal();
      }
    } on TimeoutException {
      // A later Socket.IO reconnect will retry with a fresh acknowledgement.
    } catch (_) {
      // The connection lifecycle will trigger another attempt after recovery.
    } finally {
      _recoveringConnection = false;
    }
  }

  /// Map the server's `publicSession` shape (`app/server/session.js`) onto the
  /// frozen [PartyState] — field names differ (`guests` → `participants`) and
  /// the host isn't itself in `guests`, so it's synthesized as a participant.
  void _applySession(Map<String, dynamic> json) {
    final hostId = json['hostId']?.toString() ?? '';
    final hostName = json['hostName']?.toString();
    final guestsJson = (json['guests'] as List?) ?? const [];
    final participantCandidates = <Participant>[
      if (hostId.isNotEmpty)
        Participant(userId: hostId, name: hostName ?? 'Host', isHost: true),
      ...guestsJson
          .whereType<Map>()
          .map((g) {
            final m = Map<String, dynamic>.from(g);
            final userId = m['userId']?.toString() ?? m['id']?.toString() ?? '';
            return Participant(
              userId: userId,
              name: m['name']?.toString() ?? 'Guest',
            );
          })
          .where((p) => p.userId.isNotEmpty && p.userId != hostId),
    ];
    final participantsById = <String, Participant>{
      for (final participant in participantCandidates)
        participant.userId: participant,
    };
    final participants = participantsById.values.toList(growable: false);

    final scheduleJson = json['schedule'];
    final schedule = scheduleJson is Map
        ? SyncSchedule.fromJson(Map<String, dynamic>.from(scheduleJson))
        : const SyncSchedule();

    final browseJson = json['browse'];
    final browse = browseJson is Map
        ? BrowseState.fromJson(Map<String, dynamic>.from(browseJson))
        : const BrowseState();

    // The shared browser rides alongside PartyState (see shared_browser_provider).
    _ref
        .read(sharedBrowserProvider.notifier)
        .apply(
          available: json['browserAvailable'] == true,
          browser: SharedBrowserState.fromJson(json['browser']),
        );

    final playbackJson = json['playback'];
    _playback = playbackJson is Map
        ? PlaybackInfo.fromJson(Map<String, dynamic>.from(playbackJson))
        : null;
    final preferencesJson = json['subtitlePreferences'];
    try {
      _subtitlePreferences = preferencesJson is Map
          ? SubtitlePreferences.fromJson(
              Map<String, dynamic>.from(preferencesJson),
            )
          : SubtitlePreferences.defaults;
    } on FormatException {
      _subtitlePreferences = SubtitlePreferences.defaults;
    }

    state = PartyState(
      id: json['id']?.toString() ?? state?.id ?? '',
      hostId: hostId,
      hostName: hostName,
      stage: json['stage']?.toString() ?? 'lobby',
      mediaItemId: json['mediaItemId']?.toString(),
      mediaSourceId: json['mediaSourceId']?.toString(),
      collaborativeControl: json['collaborativeControl'] == true,
      syncMode: json['syncMode']?.toString() ?? 'hopping',
      participants: participants,
      schedule: schedule,
      browse: browse,
    );

    final waitingJson = (json['waiting'] as List?) ?? const [];
    _ref
        .read(partyWaitingProvider.notifier)
        .setAll(
          waitingJson
              .whereType<Map>()
              .map((w) {
                final m = Map<String, dynamic>.from(w);
                final userId = m['userId']?.toString() ?? '';
                return Participant(
                  userId: userId,
                  name: m['name']?.toString() ?? 'Guest',
                );
              })
              .where((p) => p.userId.isNotEmpty)
              .toList(),
        );

    _syncRoleToEngine();
    _syncPlayerToMedia();
    _syncBrowserSurface();
  }

  /// True once this client has been sent to the party surface for the current
  /// shared-browser session, so a `party:state` resync cannot navigate twice.
  bool _browserSurfaceOpened = false;

  /// Pull this client onto the party surface when the party starts a shared
  /// browser.
  ///
  /// The browser is started from the popcorn, which lives in the home shell — so
  /// nobody is on `/party/:id` when the activity changes. Without this the host
  /// would press the button and stay looking at their library, and guests would
  /// never see the stream at all. Mirrors the web's `shouldOpenPartyPlayer`.
  void _syncBrowserSurface() {
    final session = state;
    if (session == null) return;
    if (session.stage != 'browser') {
      _browserSurfaceOpened = false;
      return;
    }
    if (_browserSurfaceOpened) return;
    // Waiting guests are not members yet and must not be pulled in.
    final myUserId = _myUserId;
    final isMember =
        myUserId != null &&
        (session.hostId == myUserId ||
            session.participants.any((p) => p.userId == myUserId));
    if (!isMember) return;
    _browserSurfaceOpened = true;
    // The socket handlers run for the whole app lifetime, so this resolves the
    // root navigator rather than a screen's — same as _toast.
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    // No "am I already there?" check: go() to the current location is a no-op for
    // the widget tree (same route, same key, so PartyScreen keeps its State and
    // never re-joins), and _browserSurfaceOpened already stops repeats. Reading
    // the location would need a context below a GoRoute builder, which this is
    // not guaranteed to be.
    ctx.go('/party/${session.id}');
  }

  /// The media currently opened into the shared player, so we only re-open when
  /// the selection actually changes (guards the per-update `party:state` churn).
  String? _openedMediaId;

  /// Monotonic token for shared-player intents. Every party-state change and
  /// every teardown claims a new one, so a step that has been superseded can
  /// recognise itself and stand down.
  int _mediaGeneration = 0;

  /// Tail of the SERIALIZED shared-player queue.
  ///
  /// [PlayerController.open] is not re-entrant: two overlapping opens complete
  /// in whatever order the player finishes them, which is how switching from
  /// movie A to movie B could leave the room playing A under a `party:state`
  /// that said B, and how leaving mid-open could be undone by the open it was
  /// meant to cancel. One step at a time, newest intent wins.
  Future<void> _mediaQueue = Future<void>.value();

  /// Claims the newest generation for [step] and runs it after every earlier
  /// step has finished. The returned future is [step]'s; the stored tail
  /// swallows failures so one bad open cannot wedge the queue shut forever.
  Future<void> _enqueueMediaStep(Future<void> Function(int generation) step) {
    final generation = ++_mediaGeneration;
    final queued = _mediaQueue.then((_) => step(generation));
    _mediaQueue = queued.catchError((_) {});
    return queued;
  }

  /// Loads the party's selected movie into the shared [PlayerController] — for
  /// BOTH a local pick and a remote one (the server broadcasts `party:state`
  /// with `mediaItemId`/`stage` to the whole room, so a web host's pick lands
  /// here too and a Flutter guest opens the same title). The sync engine then
  /// drives position/play from `sync:schedule`. On back-to-lobby it clears.
  Future<void> _syncPlayerToMedia() => _enqueueMediaStep(_applyMediaSelection);

  Future<void> _applyMediaSelection(int generation) async {
    // Superseded while queued — the intent that replaced us reads the same
    // `state` and will settle the player, and doing it here as well is exactly
    // the double open this queue exists to prevent.
    if (generation != _mediaGeneration) return;
    final s = state;
    if (s == null) return;
    final controller = _ref.read(playerControllerProvider);
    final mediaId = s.mediaItemId;
    final watching = s.stage == 'watching' && (mediaId ?? '').isNotEmpty;

    if (watching) {
      if (mediaId == _openedMediaId) return; // already open
      _openedMediaId = mediaId;
      try {
        // Routed through the on-device caching proxy (Phase 2), not a direct
        // signed URL — it mints/re-mints one itself as bytes are requested.
        final url = _ref
            .read(mediaCacheProxyProvider)
            .urlFor(mediaId!, mediaSourceId: s.mediaSourceId);
        // autoplay:false — the sync engine starts/positions playback from the
        // authoritative schedule, so playback stays in sync across clients.
        await controller.open(url, autoplay: false);
      } catch (_) {
        // Allow a retry on the next party:state — but only if nothing newer has
        // claimed the player in the meantime, whose bookkeeping must stand.
        if (generation == _mediaGeneration) _openedMediaId = null;
      }
    } else if (_openedMediaId != null) {
      // Back to lobby / media cleared — stop local playback.
      _openedMediaId = null;
      await controller.pause();
      await controller.seek(Duration.zero);
    }
  }

  /// Stops the shared player and forgets what was open, ordered behind any open
  /// still in flight — otherwise a leave that raced an open paused a player that
  /// then finished loading and sat there holding the movie.
  Future<void> _releaseSharedPlayer() => _enqueueMediaStep((generation) async {
    // A new session already claimed the player (solo → party handoff, or a
    // fresh join): its open is the current truth, so don't stop it.
    if (generation != _mediaGeneration) return;
    _openedMediaId = null;
    final player = _ref.read(playerControllerProvider);
    await player.pause();
    await player.seek(Duration.zero);
  });

  // ── Create / join ─────────────────────────────────────────────────────────
  /// Restores a server-side party after an app restart.
  Future<bool> resume() async {
    await _ensureConnected();
    final resp = await _socket
        .emitWithAck(ClientEvent.partyResume)
        .timeout(const Duration(seconds: 5));
    if (resp is! Map || resp['session'] is! Map) return false;
    _applySession(Map<String, dynamic>.from(resp['session'] as Map));
    await _postJoinSetup();
    return true;
  }

  /// Creates a party (optionally pre-selecting media). Returns the new
  /// `partyId`. Throws a [String] error message from the server ack on failure.
  Future<String> create({
    String? mediaItemId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _ensureConnected();
    final resp = await _socket.emitWithAck(ClientEvent.partyCreate, {
      'mediaItemId': ?mediaItemId,
      'audioStreamIndex': ?audioStreamIndex,
      'subtitleStreamIndex': ?subtitleStreamIndex,
    });
    if (resp is Map && resp['error'] != null) throw resp['error'].toString();
    final partyId = (resp as Map)['partyId']?.toString();
    if (partyId == null) throw 'party:create did not return a partyId';
    if (resp['session'] is Map) {
      _applySession(Map<String, dynamic>.from(resp['session'] as Map));
    }
    await _postJoinSetup();
    return partyId;
  }

  /// Joins an existing party. Returns `'joined'` or `'waiting'` (host approval
  /// pending — party:approved/party:rejected resolve it later).
  Future<String> join(String partyId) async {
    await _ensureConnected();
    final resp = await _socket.emitWithAck(ClientEvent.partyJoin, {
      'partyId': partyId,
    });
    if (resp is Map && resp['error'] != null) throw resp['error'].toString();
    final status = (resp as Map)['status']?.toString() ?? 'waiting';
    if (status == 'joined') {
      _pendingPartyId = null;
      if (resp['session'] is Map) {
        _applySession(Map<String, dynamic>.from(resp['session'] as Map));
      }
      await _postJoinSetup();
    } else {
      _pendingPartyId = partyId;
    }
    return status;
  }

  /// Fetches a LiveKit token and connects A/V, then attaches the sync engine
  /// to the shared [PlayerController]. Idempotent-ish: safe to call again
  /// after a role change re-derives `canControl`/`isHost`.
  Future<void> _postJoinSetup() async {
    final partyId = state?.id;
    if (partyId == null || partyId.isEmpty) return;

    final api = _ref.read(apiClientProvider);
    try {
      final token = await api.livekitToken(partyId);
      await _ref.read(livekitProvider.notifier).connect(token.url, token.token);
    } catch (e) {
      // A/V is best-effort — sync and chat still work without it, and that is
      // why this does not rethrow. But it used to `catch (_) {}`, discarding
      // the exception entirely, and "best-effort" is not the same as "silent".
      //
      // The cost of the difference: a failed token fetch or a rejected
      // /livekit/rtc upgrade left the room unconnected with nothing recorded
      // anywhere, so localParticipant stayed null and the camera and mic
      // toggles no-opped. Reported as "I am host in a party and the camera
      // does nothing, no error or warning" — and the reason was two swallowed
      // failures in a row, this one and the bare return in LivekitRoom.
      //
      // Surfaced on the LiveKit state rather than thrown, so the party still
      // works and the reason is visible where the A/V controls are.
      _ref.read(livekitProvider.notifier).reportConnectFailure(e);
    }

    final engine = _ref.read(syncEngineProvider);
    _attachedEngine = engine;
    await engine.attach(
      player: _ref.read(playerControllerProvider),
      socket: _socket,
      partyId: partyId,
      canControl: canControl,
    );
    _syncRoleToEngine();
  }

  /// Pushes the derived `isHost`/`canControl` — and the room's server-owned sync
  /// mode — onto the live engine without a re-attach. Called after every
  /// roster/host-transfer/collaborative change and every session snapshot.
  void _syncRoleToEngine() {
    final engine = _ref.read(syncEngineProvider);
    engine.canControl = canControl;
    if (engine is SyncEngineImpl) {
      engine.isHost = isHost;
      // `syncMode` is part of every session snapshot, so a join, an app-restart
      // resume, or a host transfer has to carry it. Without this the engine kept
      // its constructor default ('hopping') until a host on THIS client happened
      // to call setSyncMode — a room configured for 'dragging' was silently
      // driven with hopping semantics by everyone who joined it.
      final mode = state?.syncMode;
      if (mode != null) engine.syncMode = mode;
    }
  }

  // ── Host controls ─────────────────────────────────────────────────────────
  Future<void> approve(String userId) async {
    await _ack(ClientEvent.partyApprove, {'userId': userId});
    _ref.read(partyWaitingProvider.notifier).remove(userId);
  }

  Future<void> reject(String userId) async {
    await _ack(ClientEvent.partyReject, {'userId': userId});
    _ref.read(partyWaitingProvider.notifier).remove(userId);
  }

  Future<void> kick(String userId) =>
      _ack(ClientEvent.partyKick, {'userId': userId});

  Future<void> transferHost(String userId) =>
      _ack(ClientEvent.partyTransferHost, {'userId': userId});

  Future<void> setCollaborative(bool enabled) async {
    await _ack(ClientEvent.partySetCollaborative, {'enabled': enabled});
    final s = state;
    if (s != null) {
      state = s.copyWith(collaborativeControl: enabled);
      _syncRoleToEngine();
    }
  }

  /// Starts a brand-new party pre-seeded with whatever is already playing
  /// solo (e.g. from the detail screen's player) — `mediaItemId` + the
  /// current playback [position] carry straight in, so converting a solo
  /// watch into a party doesn't restart the movie. Reuses [create] (which
  /// pre-selects the media over `party:create`) and then re-asserts the
  /// carried-over position over the same `sync:seek` path the in-party
  /// scrubber uses — `create()`'s `party:state` reopens the stream at 0 via
  /// [_syncPlayerToMedia], so without this the position would be lost.
  Future<String> createFromCurrentPlayback({
    required String mediaItemId,
    required Duration position,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    // The shared player is already open on this item. Mark it before applying
    // the create ack so party state does not reopen the same localhost URL
    // while the solo-to-party handoff is still in progress.
    final previouslyOpened = _openedMediaId;
    _openedMediaId = mediaItemId;
    // Claim the newest shared-player intent as well: a queued open or stop left
    // over from the session being handed off would otherwise run against the
    // stream that is already playing and restart it from zero.
    _mediaGeneration++;
    late final String partyId;
    try {
      partyId = await create(
        mediaItemId: mediaItemId,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
      );
    } catch (_) {
      _openedMediaId = previouslyOpened;
      rethrow;
    }
    if (position > Duration.zero) {
      await _ref.read(syncEngineProvider).requestSeek(position);
    }
    return partyId;
  }

  Future<void> setSyncMode(String mode) async {
    await _ack(ClientEvent.partySetSyncMode, {'mode': mode});
    final s = state;
    if (s != null) state = s.copyWith(syncMode: mode);
    final engine = _ref.read(syncEngineProvider);
    if (engine is SyncEngineImpl) engine.syncMode = mode;
  }

  Future<void> selectMedia(
    String mediaItemId, {
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) {
    final payload = <String, dynamic>{'mediaItemId': mediaItemId};
    if (audioStreamIndex != null) {
      payload['audioStreamIndex'] = audioStreamIndex;
    }
    if (subtitleStreamIndex != null) {
      payload['subtitleStreamIndex'] = subtitleStreamIndex;
    }
    return _ack(ClientEvent.partySelectMedia, payload);
  }

  Future<void> setPlaybackTracks({
    required int? audioStreamIndex,
    required int subtitleStreamIndex,
  }) async {
    if (!isHost) return;
    await _ack(ClientEvent.partySetPlaybackTracks, {
      'audioStreamIndex': audioStreamIndex,
      'subtitleStreamIndex': subtitleStreamIndex,
    });
    final current = _playback;
    if (current != null) {
      _playback = current.copyWith(
        selectedAudioIndex: audioStreamIndex,
        selectedSubtitleIndex: subtitleStreamIndex,
      );
      state = state?.copyWith();
    }
  }

  Future<void> setSubtitlePreferences(SubtitlePreferences preferences) async {
    if (!isHost) return;
    await _ack(ClientEvent.partySetSubtitlePreferences, {
      'preferences': preferences.toJson(),
    });
    _subtitlePreferences = preferences;
    state = state?.copyWith();
  }

  /// "Stop Movie": back to the lobby, session (party/socket/A/V) stays alive.
  Future<void> backToLobby() => _ack(ClientEvent.partyBackToLobby);

  /// Open the shared browser for the party (host only, server-enforced).
  ///
  /// Throws the server's message on refusal — including "the shared browser is
  /// in use right now", which is the one case a caller must show verbatim rather
  /// than turn into a generic failure.
  Future<void> startSharedBrowser([String? url]) =>
      _ack(ClientEvent.browserStart, {'url': ?url});

  /// Close it and return the party to the lobby (host only).
  Future<void> stopSharedBrowser() => _ack(ClientEvent.browserStop);

  /// Point the shared browser at a URL (driver only, enforced server-side).
  Future<void> navigateSharedBrowser(String url) =>
      _ack(ClientEvent.browserNavigate, {'url': url});

  Future<void> requestBrowserControl() =>
      _ack(ClientEvent.browserRequestControl);

  Future<void> grantBrowserControl(String userId) =>
      _ack(ClientEvent.browserGrantControl, {'userId': userId});

  Future<void> denyBrowserControl(String userId) =>
      _ack(ClientEvent.browserDenyControl, {'userId': userId});

  Future<void> reclaimBrowserControl() =>
      _ack(ClientEvent.browserReclaimControl);

  // ── Driving the shared browser ─────────────────────────────────────────────
  //
  // Batched with exactly ONE emit in flight. Sending an event per pointer move
  // (~40/s) degrades the driver's own client as soon as the server or the
  // container falls behind, and an unbounded queue is the same bug with a
  // politer symptom: input arriving seconds after the gesture that produced it.

  final List<Map<String, dynamic>> _browserOutbox = [];
  bool _browserInFlight = false;
  static const int _browserMaxQueue = 64;

  /// Queue one input event, in REMOTE SCREEN coordinates.
  ///
  /// The caller does the letterbox correction, because only it knows how the
  /// stream is laid out in its own window.
  void sendBrowserInput(Map<String, dynamic> event) {
    // Only the newest cursor position matters; an older one is not worth sending.
    if (event['type'] == 'move' &&
        _browserOutbox.isNotEmpty &&
        _browserOutbox.last['type'] == 'move') {
      _browserOutbox[_browserOutbox.length - 1] = event;
    } else {
      _browserOutbox.add(event);
    }
    // Never grow without bound, and drop the oldest MOVE rather than a click or a
    // keystroke — those are the events a user would notice losing.
    while (_browserOutbox.length > _browserMaxQueue) {
      final index = _browserOutbox.indexWhere((e) => e['type'] == 'move');
      _browserOutbox.removeAt(index == -1 ? 0 : index);
    }
    _flushBrowserInput();
  }

  void _flushBrowserInput() {
    if (_browserInFlight || _browserOutbox.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_browserOutbox);
    _browserOutbox.clear();
    _browserInFlight = true;
    // A timeout is required, not defensive: emitWithAck never completes if the
    // connection drops mid-flight, which would wedge this queue shut for the rest
    // of the session.
    _socket
        .emitWithAck(ClientEvent.browserInput, {'events': batch})
        .timeout(const Duration(seconds: 2))
        .catchError((_) => null)
        .whenComplete(() {
          _browserInFlight = false;
          _flushBrowserInput();
        });
  }

  /// "Stop Stream": host ends the party for everyone.
  Future<void> end() async {
    await _ack(ClientEvent.partyEnd);
    await _leaveLocal();
  }

  /// A guest leaving voluntarily — there's no server "leave" event in the
  /// contract (party membership is scoped to this socket's lifetime), so
  /// leaving means tearing down local party state, A/V, sync, and the socket.
  Future<void> leave() => _leaveLocal();

  Future<void> _ack(String event, [Object? data]) async {
    final resp = await _socket.emitWithAck(event, data ?? const {});
    if (resp is Map && resp['error'] != null) throw resp['error'].toString();
  }

  /// Release everything this client holds for the party: the sync engine, the
  /// shared player, the LiveKit room, chat, and the socket itself.
  ///
  /// Every step is guarded independently, for the same reason `main.dart`'s
  /// shutdown handler guards its own: one step throwing must not skip the ones
  /// after it. Losing this teardown part-way through is how leaving a party —
  /// or signing out — could leave the camera live or the socket connected.
  Future<void> _leaveLocal() async {
    _pendingPartyId = null;
    final engine = _ref.read(syncEngineProvider);
    // Cleared before (and outside) the guarded detach: dropping our reference
    // must not depend on detach succeeding, or a throwing engine would leave a
    // stale _attachedEngine behind for dispose() to detach a second time.
    _attachedEngine = null;
    await _bestEffort(() async {
      await engine.detach();
      if (engine is SyncEngineImpl) engine.isHost = false;
    });
    // The shared PlayerController lives for the app's lifetime (it's a plain
    // Provider, not scoped to the party) — detaching the sync engine only
    // stops the party from *driving* it, so without an explicit stop here the
    // movie (and its audio) keeps playing after leaving/ending the party.
    //
    // Queued behind any open still in flight (see [_releaseSharedPlayer]), with
    // a bound on the wait: teardown must release the socket and the camera even
    // if the player itself never finishes loading.
    await _bestEffort(
      () => _releaseSharedPlayer().timeout(const Duration(seconds: 5)),
    );
    await _bestEffort(() async {
      await _ref.read(livekitProvider.notifier).leave();
      _ref.read(livekitProvider.notifier).reset();
    });
    await _bestEffort(() => _ref.read(chatProvider.notifier).clear());
    _unsubscribe();
    await _bestEffort(() => _socket.disconnect());
    clear();
  }

  Future<void> _bestEffort(FutureOr<void> Function() step) async {
    try {
      await step();
    } catch (_) {
      // Deliberately swallowed: see [_leaveLocal].
    }
  }

  String _participantName(String userId) {
    final s = state;
    if (s == null) return userId;
    for (final p in s.participants) {
      if (p.userId == userId) return p.name;
    }
    return userId;
  }

  /// App-wide party activity toast (mirrors `PartyContext`'s reducer toasts):
  /// fired from the socket handlers, which run for the whole app lifetime, so it
  /// resolves the root navigator context rather than a screen's. The discrete
  /// join/leave/host/kick/reject/end events are one-shot server broadcasts (not
  /// part of the `party:state` resync), so a reconnect never re-fires them.
  void _toast(String message, {String level = 'info'}) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    showAnalogToast(
      ctx,
      message,
      tone: switch (level) {
        'success' => AnalogToastTone.success,
        'warning' => AnalogToastTone.warning,
        'error' => AnalogToastTone.danger,
        _ => AnalogToastTone.info,
      },
    );
  }

  @override
  void dispose() {
    _unsubscribe();
    // Disposing the party without detaching left the sync engine's 200ms
    // control loop, applying timers, and clock ping running against a player
    // and socket this notifier no longer manages. `dispose` is synchronous, so
    // the detach is fire-and-forget; it cancels its timers before its first
    // await either way.
    final engine = _attachedEngine;
    _attachedEngine = null;
    if (engine != null) unawaited(engine.detach());
    super.dispose();
  }
}

final partyProvider = StateNotifierProvider<PartyNotifier, PartyState?>(
  (ref) => PartyNotifier(ref),
);

/// Guests awaiting host approval (server's `party:waiting` broadcasts + the
/// `waiting[]` field on a full `party:state` snapshot). Host-only UI concern.
class PartyWaitingNotifier extends StateNotifier<List<Participant>> {
  PartyWaitingNotifier() : super(const []);

  void add(Participant p) {
    if (state.any((e) => e.userId == p.userId)) return;
    state = [...state, p];
  }

  void remove(String userId) =>
      state = state.where((e) => e.userId != userId).toList();

  void setAll(List<Participant> list) {
    state = <String, Participant>{
      for (final participant in list) participant.userId: participant,
    }.values.toList(growable: false);
  }

  void clear() => state = const [];
}

final partyWaitingProvider =
    StateNotifierProvider<PartyWaitingNotifier, List<Participant>>(
      (ref) => PartyWaitingNotifier(),
    );

/// The id of the party whose immersive surface this client has deliberately
/// MINIMIZED away from, or null.
///
/// The party screen's top-left Back is a minimize: the session — socket, A/V,
/// sync engine, playback — stays live behind the popcorn. Something has to stop
/// the shell's auto-open from dragging the user straight back in, and it cannot
/// be `_AppShellState` state: `/party/:id` is a top-level route, so navigating
/// to it REPLACES the shell, and the shell is built from scratch on the way
/// back with no memory of why it was entered.
class PartyMinimizedNotifier extends StateNotifier<String?> {
  PartyMinimizedNotifier() : super(null);

  void minimize(String partyId) => state = partyId;

  /// Re-entering the player, the room leaving the player surface, and the
  /// session ending all clear the latch, so the next `watching` stage opens
  /// normally again.
  void restore() => state = null;
}

final partyMinimizedProvider =
    StateNotifierProvider<PartyMinimizedNotifier, String?>(
      (ref) => PartyMinimizedNotifier(),
    );

/// The sync engine driving playback from the party timeline (PLAN §3.4). The
/// real host-authority [SyncEngineImpl] (E5.1); [PartyNotifier] attaches it
/// and keeps `isHost`/`canControl` current.
///
/// Disposing the container (logout teardown, app shutdown, a test's
/// `addTearDown`) disposes the engine with it: its control loop, applying
/// timers, socket handlers, and server-clock ping all outlived the provider
/// otherwise, and kept driving whatever player they were last attached to.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngineImpl();
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});
