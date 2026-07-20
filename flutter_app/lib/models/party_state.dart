import 'package:freezed_annotation/freezed_annotation.dart';

import 'participant.dart';

part 'party_state.freezed.dart';
part 'party_state.g.dart';

/// The shared playback timeline every client locks onto. Emitted by the server
/// as `sync:schedule` (`app/server/index.js` setSchedule). Positions are in
/// Jellyfin ticks (1 tick = 100ns → 10 000 ticks per ms).
@freezed
class SyncSchedule with _$SyncSchedule {
  const factory SyncSchedule({
    @Default(0) int positionTicks,
    /// Server epoch-ms when the current play segment started (0 when paused).
    @Default(0) int t0,
    /// Playback rate: 1 while playing, 0 while paused/stalled.
    @Default(0) int rate,
    @Default(true) bool paused,
    /// 'playing' | 'paused' | 'stalled'
    @Default('paused') String phase,
    /// Monotonic version; a controller may gate a command on it (baseVersion).
    @Default(0) int version,
    /// Bumped whenever the media selection changes (guards stale stalls).
    @Default(0) int mediaGeneration,
  }) = _SyncSchedule;

  factory SyncSchedule.fromJson(Map<String, dynamic> json) =>
      _$SyncScheduleFromJson(json);
}

/// The shared browse (lobby "shared screen") drill state.
@freezed
class BrowseState with _$BrowseState {
  const factory BrowseState({
    @Default([]) List<Map<String, dynamic>> stack,
  }) = _BrowseState;

  factory BrowseState.fromJson(Map<String, dynamic> json) =>
      _$BrowseStateFromJson(json);
}

/// Client-facing view of a party session — the shape of the server's
/// `publicSession()` (`app/server/session.js`) plus the derived participant
/// list. Host token / internal timeline scratch fields are never sent.
@freezed
class PartyState with _$PartyState {
  const factory PartyState({
    required String id,
    required String hostId,
    String? hostName,
    /// 'lobby' | 'watching'
    @Default('lobby') String stage,
    /// 'none' | 'remote-browser'. Only sent to clients that connect with
    /// `caps: { remoteBrowser: true }` (see `socketOptionsFor()`); legacy
    /// clients never see anything but the B0 lobby fallback.
    @Default('none') String activity,
    String? mediaItemId,
    String? mediaSourceId,
    @Default(false) bool collaborativeControl,
    /// 'hopping' | 'dragging'
    @Default('hopping') String syncMode,
    @Default(<Participant>[]) List<Participant> participants,
    @Default(SyncSchedule()) SyncSchedule schedule,
    @Default(BrowseState()) BrowseState browse,
  }) = _PartyState;

  factory PartyState.fromJson(Map<String, dynamic> json) =>
      _$PartyStateFromJson(json);
}
