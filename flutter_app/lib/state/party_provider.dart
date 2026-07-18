import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sc;

import '../app/router.dart';
import '../models/models.dart';
import '../net/events.dart';
import '../net/socket_client.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_impl.dart';
import '../ui/tokens.dart';
import 'chat_provider.dart';
import 'livekit_provider.dart';
import 'player_provider.dart';
import 'providers.dart';

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
  bool _subscribed = false;

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
    _playback = null;
    _subtitlePreferences = SubtitlePreferences.defaults;
    _ref.read(partyWaitingProvider.notifier).clear();
  }

  // ── Socket subscription (idempotent) ─────────────────────────────────────
  Future<void> _ensureConnected() async {
    if (!_socket.isConnected) await _socket.connect();
    if (!_subscribed) _subscribe();
  }

  void _subscribe() {
    _subscribed = true;
    final socket = _socket;
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
  }

  void _unsubscribe() {
    for (final u in _unsubs) {
      u();
    }
    _unsubs.clear();
    _subscribed = false;
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
  }

  /// The media currently opened into the shared player, so we only re-open when
  /// the selection actually changes (guards the per-update `party:state` churn).
  String? _openedMediaId;

  /// Loads the party's selected movie into the shared [PlayerController] — for
  /// BOTH a local pick and a remote one (the server broadcasts `party:state`
  /// with `mediaItemId`/`stage` to the whole room, so a web host's pick lands
  /// here too and a Flutter guest opens the same title). The sync engine then
  /// drives position/play from `sync:schedule`. On back-to-lobby it clears.
  Future<void> _syncPlayerToMedia() async {
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
        _openedMediaId = null; // allow a retry on the next party:state
      }
    } else if (_openedMediaId != null) {
      // Back to lobby / media cleared — stop local playback.
      _openedMediaId = null;
      await controller.pause();
      await controller.seek(Duration.zero);
    }
  }

  // ── Create / join ─────────────────────────────────────────────────────────
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
      if (resp['session'] is Map) {
        _applySession(Map<String, dynamic>.from(resp['session'] as Map));
      }
      await _postJoinSetup();
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
    } catch (_) {
      // A/V is best-effort — sync + chat still work without it.
    }

    final engine = _ref.read(syncEngineProvider);
    await engine.attach(
      player: _ref.read(playerControllerProvider),
      socket: _socket,
      partyId: partyId,
      canControl: canControl,
    );
    _syncRoleToEngine();
  }

  /// Pushes the derived `isHost`/`canControl` onto the live engine without a
  /// re-attach — called after every roster/host-transfer/collaborative change.
  void _syncRoleToEngine() {
    final engine = _ref.read(syncEngineProvider);
    engine.canControl = canControl;
    if (engine is SyncEngineImpl) engine.isHost = isHost;
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

  Future<void> _leaveLocal() async {
    final engine = _ref.read(syncEngineProvider);
    await engine.detach();
    if (engine is SyncEngineImpl) engine.isHost = false;
    // The shared PlayerController lives for the app's lifetime (it's a plain
    // Provider, not scoped to the party) — detaching the sync engine only
    // stops the party from *driving* it, so without an explicit stop here the
    // movie (and its audio) keeps playing after leaving/ending the party.
    await _ref.read(playerControllerProvider).pause();
    await _ref.read(playerControllerProvider).seek(Duration.zero);
    _openedMediaId = null;
    await _ref.read(livekitProvider.notifier).leave();
    _ref.read(livekitProvider.notifier).reset();
    _ref.read(chatProvider.notifier).clear();
    _unsubscribe();
    await _socket.disconnect();
    clear();
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
    final Color dot = switch (level) {
      'success' => AppColors.green,
      'warning' || 'error' => AppColors.red,
      _ => AppColors.faint,
    };
    sc.showToast(
      context: ctx,
      location: sc.ToastLocation.topCenter,
      builder: (context, overlay) => sc.SurfaceCard(
        surfaceBlur: AppBlur.overlay,
        surfaceOpacity: 0.9,
        borderColor: AppColors.line2,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _unsubscribe();
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

/// The sync engine driving playback from the party timeline (PLAN §3.4). The
/// real host-authority [SyncEngineImpl] (E5.1); [PartyNotifier] attaches it
/// and keeps `isHost`/`canControl` current.
final syncEngineProvider = Provider<SyncEngine>((ref) => SyncEngineImpl());
