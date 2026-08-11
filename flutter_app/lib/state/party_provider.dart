import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analog/chrome/analog_toast.dart';
import '../app/router.dart';
import '../models/models.dart';
import '../net/events.dart';
import '../net/socket_client.dart';
import 'chat_provider.dart';
import 'livekit_provider.dart';
import 'providers.dart';

/// Watch-party lifecycle over the socket (PLAN §3.8, E5.2). Owns
/// create/join/approve/reject/kick/end/transferHost/setCollaborative/
/// the participant roster, host detection, chat, and A/V setup. Movie playback
/// is deliberately owned outside the party lifecycle.
class PartyNotifier extends StateNotifier<PartyState?> {
  PartyNotifier(this._ref, {this.ackTimeout = const Duration(seconds: 5)})
    : super(null);

  final Ref _ref;
  final Duration ackTimeout;
  final List<void Function()> _unsubs = [];

  StreamSubscription<bool>? _connectionSubscription;
  bool _subscribed = false;
  bool _recoveringConnection = false;
  int _generation = 0;
  Future<void>? _teardown;
  String? __pendingPartyId;

  /// The room this client has asked to join and is waiting on.
  ///
  /// Published through [partyPendingProvider] rather than kept private,
  /// because SOMETHING has to tell the guest they are waiting. This used to be
  /// a whole screen — the sonar waiting room on `/party/:id` — and when that
  /// route was deleted the state went unrendered: you typed a code, the dialog
  /// closed, and the app looked exactly as it had before you asked. Silence is
  /// the one response a request for permission must never get.
  String? get _pendingPartyId => __pendingPartyId;
  set _pendingPartyId(String? value) {
    if (__pendingPartyId == value) return;
    __pendingPartyId = value;
    _ref.read(partyPendingProvider.notifier).state = value;
  }

  SocketClient get _socket => _ref.read(socketClientProvider);
  String? get _myUserId => _ref.read(currentUserIdProvider);

  /// True once a session snapshot has been applied for a party this client is
  /// part of (lobby or watching).
  bool get inParty => state != null;

  bool get isHost =>
      state != null && _myUserId != null && state!.hostId == _myUserId;

  // ── Direct state mutations (kept for tests / callers that already have a
  // ready-made snapshot) ────────────────────────────────────────────────────
  void setState(PartyState? party) {
    state = party;
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
    _ref.read(partyWaitingProvider.notifier).clear();
    _ref.read(chatDrawerOpenProvider.notifier).state = false;
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
        final pendingPartyId = _pendingPartyId;
        if (pendingPartyId == null) return;
        _pendingPartyId = null;
        if (data is Map && data['session'] is Map) {
          _applySession(Map<String, dynamic>.from(data['session'] as Map));
        }
        final partyId = state?.id;
        if (partyId == null || partyId.isEmpty) return;
        final generation = _generation;
        unawaited(_postJoinSetup(generation, partyId));
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
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _subscribed = false;
  }

  Future<void> _recoverAfterReconnect() async {
    if (_recoveringConnection) return;
    _recoveringConnection = true;
    final generation = _generation;
    try {
      final pendingPartyId = _pendingPartyId;
      if (pendingPartyId != null) {
        final resp = await _socket
            .emitWithAck(ClientEvent.partyJoin, {'partyId': pendingPartyId})
            .timeout(const Duration(seconds: 5));
        if (generation != _generation || _pendingPartyId != pendingPartyId) {
          return;
        }
        if (resp is Map &&
            resp['status'] == 'joined' &&
            resp['session'] is Map) {
          _pendingPartyId = null;
          _applySession(Map<String, dynamic>.from(resp['session'] as Map));
          final partyId = state?.id;
          if (partyId != null && partyId.isNotEmpty) {
            await _postJoinSetup(generation, partyId);
          }
        }
        return;
      }

      final resp = await _socket
          .emitWithAck(ClientEvent.partyResume)
          .timeout(const Duration(seconds: 5));
      if (generation != _generation || state == null) return;
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
    );
    final partyId = state?.id;
    if (partyId != null && partyId.isNotEmpty) {
      _ref.read(chatProvider.notifier).activate(partyId);
    }

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
  }

  // ── Create / join ─────────────────────────────────────────────────────────
  /// Restores a server-side party after an app restart.
  Future<bool> resume() async {
    await _teardown;
    final generation = ++_generation;
    await _ensureConnected();
    _ref.read(chatProvider.notifier).prepareForJoin();
    final resp = await _socket
        .emitWithAck(ClientEvent.partyResume)
        .timeout(const Duration(seconds: 5));
    if (generation != _generation) return false;
    if (resp is! Map || resp['session'] is! Map) {
      _ref.read(chatProvider.notifier).deactivate();
      return false;
    }
    _applySession(Map<String, dynamic>.from(resp['session'] as Map));
    final partyId = state?.id;
    if (partyId == null || partyId.isEmpty) return false;
    await _postJoinSetup(generation, partyId);
    if (generation != _generation || state?.id != partyId) return false;
    return true;
  }

  /// Creates a party (optionally pre-selecting media). Returns the new
  /// `partyId`. Throws a [String] error message from the server ack on failure.
  Future<String> create({
    String? mediaItemId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) async {
    await _teardown;
    final generation = ++_generation;
    await _ensureConnected();
    _ref.read(chatProvider.notifier).prepareForJoin();
    final resp = await _socket.emitWithAck(ClientEvent.partyCreate, {
      'mediaItemId': ?mediaItemId,
      'audioStreamIndex': ?audioStreamIndex,
      'subtitleStreamIndex': ?subtitleStreamIndex,
    });
    if (generation != _generation) throw StateError('Party creation cancelled');
    if (resp is Map && resp['error'] != null) {
      _ref.read(chatProvider.notifier).deactivate();
      throw resp['error'].toString();
    }
    final partyId = (resp as Map)['partyId']?.toString();
    if (partyId == null) {
      _ref.read(chatProvider.notifier).deactivate();
      throw 'party:create did not return a partyId';
    }
    if (resp['session'] is Map) {
      _applySession(Map<String, dynamic>.from(resp['session'] as Map));
    }
    await _postJoinSetup(generation, partyId);
    if (generation != _generation || state?.id != partyId) {
      throw StateError('Party creation cancelled');
    }
    return partyId;
  }

  /// Joins an existing party. Returns `'joined'` or `'waiting'` (host approval
  /// pending — party:approved/party:rejected resolve it later).
  Future<String> join(String partyId) async {
    await _teardown;
    final generation = ++_generation;
    await _ensureConnected();
    _ref.read(chatProvider.notifier).prepareForJoin();
    final resp = await _socket.emitWithAck(ClientEvent.partyJoin, {
      'partyId': partyId,
    });
    if (generation != _generation) throw StateError('Party join cancelled');
    if (resp is Map && resp['error'] != null) {
      _ref.read(chatProvider.notifier).deactivate();
      throw resp['error'].toString();
    }
    final status = (resp as Map)['status']?.toString() ?? 'waiting';
    if (status == 'joined') {
      _pendingPartyId = null;
      if (resp['session'] is Map) {
        _applySession(Map<String, dynamic>.from(resp['session'] as Map));
      }
      final joinedPartyId = state?.id;
      if (joinedPartyId != null && joinedPartyId.isNotEmpty) {
        await _postJoinSetup(generation, joinedPartyId);
      }
      if (generation != _generation || state?.id != joinedPartyId) {
        throw StateError('Party join cancelled');
      }
    } else {
      _pendingPartyId = partyId;
      _ref.read(chatProvider.notifier).deactivate();
    }
    return status;
  }

  /// Fetches a LiveKit token and connects A/V.
  Future<void> _postJoinSetup(int generation, String partyId) async {
    final api = _ref.read(apiClientProvider);
    try {
      final token = await api.livekitToken(partyId);
      if (generation != _generation || state?.id != partyId) return;
      await _ref.read(livekitProvider.notifier).connect(token.url, token.token);
      if (generation != _generation || state?.id != partyId) {
        await _ref.read(livekitProvider.notifier).leave();
      }
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
  }

  /// Guards against a second reconnect starting while one is in flight —
  /// pressing the button twice would otherwise race two joins into the same
  /// room and leave a ghost participant behind.
  bool _reconnectingAv = false;

  /// Tear down and re-establish the A/V room ALONE, on a fresh token.
  ///
  /// The failure this exists for: a participant whose publish path is wedged —
  /// a camera that will not come back — while
  /// everything else about the party is fine. The only remedy used to be
  /// ending the party and starting over, which punishes the whole room for one
  /// person's broken track.
  ///
  /// Deliberately narrow. The socket, party session, chat, and local movie are
  /// untouched. Only this client's LiveKit room is rebuilt.
  ///
  /// The token is re-fetched rather than reused. A stale token is one of the
  /// ways the room gets into this state to begin with, and re-issuing costs one
  /// request.
  ///
  /// Mic and camera are restored to what they were, because a reconnect is a
  /// repair and not a settings change — coming back with the mic live after the
  /// user had muted would be the worst possible surprise.
  ///
  /// Returns null on success, or a message describing the failure.
  Future<String?> reconnectAv() async {
    final partyId = state?.id;
    if (partyId == null || partyId.isEmpty) {
      return 'You are not in a party.';
    }
    if (_reconnectingAv) return null;
    _reconnectingAv = true;
    final generation = _generation;

    final livekit = _ref.read(livekitProvider.notifier);
    final before = _ref.read(livekitProvider);
    try {
      // Leave first, and do not let a failure here stop the rejoin: the room
      // being unusable is the whole reason we are here, so a disconnect that
      // throws is expected rather than exceptional.
      try {
        await livekit.leave();
      } catch (_) {}

      final token = await _ref.read(apiClientProvider).livekitToken(partyId);
      if (generation != _generation || state?.id != partyId) {
        return 'The party was closed.';
      }
      await livekit.connect(token.url, token.token);
      if (!_ref.read(livekitProvider).connected) {
        return _ref.read(livekitProvider).error ??
            'Video chat did not connect.';
      }
      if (generation != _generation || state?.id != partyId) {
        await livekit.leave();
        return 'The party was closed.';
      }
      await livekit.setMic(before.micEnabled);
      await livekit.setCamera(before.cameraEnabled);
      return null;
    } catch (e) {
      // Same reasoning as _postJoinSetup: surfaced on the LiveKit state so the
      // reason appears where the A/V controls are, never thrown at the caller.
      livekit.reportConnectFailure(e);
      return '$e';
    } finally {
      _reconnectingAv = false;
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

  /// Put a title on the room's timeline.
  ///
  /// The driver does NOT open the player itself — it tells the server, and the
  /// `party:state` that comes back opens it here exactly as it opens it for
  /// everyone else. One path for the host and the guests means the room cannot
  /// end up watching two different things because one of them took a shortcut.
  Future<void> selectMedia({
    required String mediaItemId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) => _ack(ClientEvent.partySelectMedia, {
    'mediaItemId': mediaItemId,
    'audioStreamIndex': ?audioStreamIndex,
    'subtitleStreamIndex': ?subtitleStreamIndex,
  });

  /// Take the title off the room's timeline, for everyone. What the host's
  /// Close means while a party is running.
  Future<void> backToLobby() => _ack(ClientEvent.partyBackToLobby);

  Future<void> transferHost(String userId) =>
      _ack(ClientEvent.partyTransferHost, {'userId': userId});

  /// "Stop Stream": host ends the party for everyone.
  Future<void> end() async {
    final generation = _generation;
    Object? failure;
    try {
      await _ack(ClientEvent.partyEnd);
    } catch (error) {
      failure = error;
    }
    if (generation == _generation) await _leaveLocal();
    if (failure != null) throw failure;
  }

  /// A guest leaving voluntarily — there's no server "leave" event in the
  /// contract (party membership is scoped to this socket's lifetime), so
  /// leaving means tearing down local party state, A/V, sync, and the socket.
  Future<void> leave() => _leaveLocal();

  Future<void> _ack(String event, [Object? data]) async {
    final resp = await _socket
        .emitWithAck(event, data ?? const {})
        .timeout(ackTimeout);
    if (resp is Map && resp['error'] != null) throw resp['error'].toString();
  }

  /// Release everything this client holds for the party: LiveKit, chat, and the
  /// socket itself. Local playback is intentionally untouched.
  ///
  /// Every step is guarded independently, for the same reason `main.dart`'s
  /// shutdown handler guards its own: one step throwing must not skip the ones
  /// after it. Losing this teardown part-way through is how leaving a party —
  /// or signing out — could leave the camera live or the socket connected.
  Future<void> _leaveLocal() {
    final activeTeardown = _teardown;
    if (activeTeardown != null) return activeTeardown;
    _generation++;
    _pendingPartyId = null;
    state = null;
    _ref.read(chatDrawerOpenProvider.notifier).state = false;
    _ref.read(partyWaitingProvider.notifier).clear();
    _ref.read(chatProvider.notifier).deactivate();
    _unsubscribe();
    final teardown = _performLeave();
    _teardown = teardown;
    return teardown.whenComplete(() {
      if (identical(_teardown, teardown)) _teardown = null;
    });
  }

  Future<void> _performLeave() async {
    await _bestEffort(() async {
      final livekit = _ref.read(livekitProvider.notifier);
      try {
        await livekit.leave().timeout(const Duration(seconds: 5));
      } finally {
        livekit.reset();
      }
    });
    await _bestEffort(() => _ref.read(chatProvider.notifier).clear());
    await _bestEffort(() => _socket.disconnect());
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

/// The room this client has asked to join and is waiting for approval on, or
/// null. Distinct from [partyProvider], which stays null until you are actually
/// let in — being admitted is the transition between the two.
final partyPendingProvider = StateProvider<String?>((ref) => null);

/// Whether the chat drawer is on screen.
///
/// The notification rail reads it: a message you are already looking at does
/// not need announcing. It lives here rather than in the party screen's own
/// state because the rail sits above the router and cannot see into a route.
final chatDrawerOpenProvider = StateProvider<bool>((ref) => false);
