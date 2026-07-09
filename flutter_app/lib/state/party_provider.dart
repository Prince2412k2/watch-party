import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../sync/sync_engine.dart';
import '../sync/sync_engine_impl.dart';

/// Watch-party state (PLAN §3.8). Phase 0 holds a nullable [PartyState] and a
/// mock [SyncEngine]; E5 fills create/join/host-authority. Surface frozen.
class PartyNotifier extends StateNotifier<PartyState?> {
  PartyNotifier() : super(null);

  /// Replace the whole session snapshot (server `party:state` / `sync:schedule`).
  void setState(PartyState? party) => state = party;

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
        participants: s.participants.where((e) => e.userId != userId).toList());
  }

  void clear() => state = null;
}

final partyProvider =
    StateNotifierProvider<PartyNotifier, PartyState?>((ref) => PartyNotifier());

/// The sync engine driving playback from the party timeline. E5.1 fills the
/// real host-authority engine (Phase 0 shipped a passive [MockSyncEngine]).
final syncEngineProvider = Provider<SyncEngine>((ref) => SyncEngineImpl());
