/// FROZEN CONTRACT (PLAN §3.5) — the socket.io event vocabulary, transcribed
/// verbatim from the existing backend (`app/server/index.js`). These names and
/// payloads are the sync + party + chat wire protocol; the Flutter client must
/// match them exactly. Auth is via the shared session cookie on the socket.io
/// handshake (the server's `io.use` middleware reads `req.session.jellyfin`).
///
/// Positions are Jellyfin ticks (10 000 ticks per ms) everywhere sync is
/// involved.
///
/// ── CLIENT → SERVER (emit; many take an ack callback) ────────────────────
///   party:create        { mediaItemId? }            ack: { partyId, session } | { error }
///   party:join          { partyId }                 ack: { status: 'joined'|'waiting', session? } | { error }
///   party:approve       { userId }                  ack: { ok } | { error }        (host only)
///   party:reject        { userId }                  ack: { ok } | { error }        (host only)
///   party:kick          { userId }                  ack: { ok } | { error }        (host only)
///   party:end           (none)                      ack: { ok } | { error }        (host only)
///   party:transferHost  { userId }                  ack: { ok } | { error }        (host only)
///   party:setCollaborative { enabled }              ack: { ok } | { error }        (host only)
///   party:setSyncMode   { mode: 'hopping'|'dragging' } ack: { ok } | { error }     (host only)
///   party:selectMedia   { mediaItemId }             ack: { ok } | { error }        (driver)
///   party:backToLobby   (none)                      ack: { ok } | { error }        (driver)
///   clock:ping          t1                          ack: serverNowMs               (NTP-lite)
///   sync:hello          (none)                      → server replies sync:schedule
///   sync:play           { positionTicks, baseVersion?, commandId? } ack: { ok, version } | { error }
///   sync:pause          { positionTicks, baseVersion?, commandId? } ack: { ok, version } | { error }
///   sync:seek           { positionTicks, baseVersion?, commandId? } ack: { ok, version } | { error }
///   sync:report         { position, drift, rate }   (telemetry, no ack)
///   sync:stall          { ...stallReport }          (drives dragging mode)
///   browse:navigate     { stack: [{id,name,type}, …≤8] }  (driver; relayed)
///   browse:pointer      { scroll, x, y }            (driver; ephemeral relay)
///   chat:message        { text }                    ack: { ok } | { error: 'rate limited' }
///   camera:remove       { userId }                  ack: { ok } | { error }        (host only)
///
/// ── SERVER → CLIENT (on) ─────────────────────────────────────────────────
///   sync:schedule       { positionTicks, t0, rate, paused, phase, version, mediaGeneration }
///   sync:host_gone      (none)                      host disconnected; room frozen+paused
///   sync:stall_fallback { memberIds: [], mediaGeneration }
///   party:state         publicSession (see PartyState)  full session snapshot
///   party:waiting       { userId, name }            (host: a guest is requesting)
///   party:approved      { session }                 (guest: admitted)
///   party:rejected      {}                           (guest: denied)
///   party:kicked        { userId }                   (guest: removed)
///   party:ended         {}                           (host ended the party)
///   host:changed        { hostId }                   host migrated / transferred
///   user:joined         { userId, name }
///   user:left           { userId, name }
///   browse:state        { stack: [...] }             mirrored shared-screen drill
///   browse:pointer      { scroll, x, y }             mirrored cursor
///   chat:message        { userId, name, text, timestamp }
///   camera:removed      { userId }
///
/// The `publicSession` shape (from `app/server/session.js`) contains: id,
/// hostId, hostName, hostDeviceId, hostSocketId, mediaItemId, mediaSourceId,
/// stage, browse, guests[], waiting[], messages[], schedule, syncMode,
/// collaborativeControl, stallFallback[]. Fields hostToken/intent/pos/etc are
/// stripped server-side.
library;

/// Client → server event names.
abstract final class ClientEvent {
  static const partyCreate = 'party:create';
  static const partyJoin = 'party:join';
  static const partyApprove = 'party:approve';
  static const partyReject = 'party:reject';
  static const partyKick = 'party:kick';
  static const partyEnd = 'party:end';
  static const partyTransferHost = 'party:transferHost';
  static const partySetCollaborative = 'party:setCollaborative';
  static const partySetSyncMode = 'party:setSyncMode';
  static const partySelectMedia = 'party:selectMedia';
  static const partyBackToLobby = 'party:backToLobby';
  static const clockPing = 'clock:ping';
  static const syncHello = 'sync:hello';
  static const syncPlay = 'sync:play';
  static const syncPause = 'sync:pause';
  static const syncSeek = 'sync:seek';
  static const syncReport = 'sync:report';
  static const syncStall = 'sync:stall';
  static const browseNavigate = 'browse:navigate';
  static const browsePointer = 'browse:pointer';
  static const chatMessage = 'chat:message';
  static const cameraRemove = 'camera:remove';
}

/// Server → client event names.
abstract final class ServerEvent {
  static const syncSchedule = 'sync:schedule';
  static const syncHostGone = 'sync:host_gone';
  static const syncStallFallback = 'sync:stall_fallback';
  static const partyState = 'party:state';
  static const partyWaiting = 'party:waiting';
  static const partyApproved = 'party:approved';
  static const partyRejected = 'party:rejected';
  static const partyKicked = 'party:kicked';
  static const partyEnded = 'party:ended';
  static const hostChanged = 'host:changed';
  static const userJoined = 'user:joined';
  static const userLeft = 'user:left';
  static const browseState = 'browse:state';
  static const browsePointer = 'browse:pointer';
  static const chatMessage = 'chat:message';
  static const cameraRemoved = 'camera:removed';
}

/// Jellyfin tick conversions (1 tick = 100ns).
const int ticksPerMs = 10000;

int durationToTicks(Duration d) => d.inMilliseconds * ticksPerMs;
Duration ticksToDuration(int ticks) =>
    Duration(milliseconds: ticks ~/ ticksPerMs);
