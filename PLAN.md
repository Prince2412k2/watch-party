# Watchparty — End-to-End Implementation Plan

> Technical/architecture plan. **Visual & UX design is intentionally left open** —
> all `*.jsx` components below specify behavior, props, and state only. Styling,
> layout aesthetics, and component look-and-feel come from design later.

Verified against the live stack (Phase 1 risk checks). Two handoff corrections
are already baked in:
- **Playback** uses `POST /SyncPlay/SetNewQueue` (not `/SyncPlay/Play`).
- **HLS URL** requires `MediaSourceId`: `/Videos/{id}/master.m3u8?MediaSourceId={id}&api_key={token}&...`

---

## 0. System Topology

```
┌─────────────┐   HTTP/WS    ┌──────────────────────┐   REST + WS    ┌──────────┐
│   Browser   │ ───────────▶ │   App Server (3000)  │ ─────────────▶ │ Jellyfin │
│  (React)    │ ◀─────────── │  Express + Socket.io │ ◀───────────── │  (8096)  │
└─────────────┘   Socket.io  └──────────────────────┘  /socket bridge└──────────┘
       │                              │  mints tokens
       │  WebRTC (media)              ▼
       │                       ┌──────────────┐
       └─────────────────────▶ │   LiveKit    │  (cameras/mic only)
                               │   (7880)     │
                               └──────────────┘
```

- Browser holds **one** Socket.io connection to the app server. It never speaks to
  Jellyfin's WS directly — the server bridges SyncPlay events.
- Browser streams **video** straight from Jellyfin (HLS) and **camera media**
  straight from LiveKit. The app server proxies neither; it only coordinates.

---

## 1. Server Architecture

### 1.1 `server/index.js` — entry / wiring
- Express app + HTTP server + Socket.io server.
- Middleware: `express.json`, `cookie-parser`, session.
- Mounts REST routers from `auth.js`, `library` endpoints, `livekit.js`.
- Socket.io auth handshake → attaches `socket.user` (from cookie/session).
- Registers Socket.io event handlers (delegates to `session.js`, `syncplay.js`).
- Single in-memory store: `Map<partyId, Session>` (see §3).

### 1.2 `server/auth.js` — Jellyfin auth proxy
- `POST /api/auth/login` → proxies `POST /Users/AuthenticateByName` to Jellyfin
  with `X-Emby-Authorization` header. On success, stores
  `{ accessToken, userId, name, isAdmin }` in the server session and sets an
  httpOnly cookie. Returns sanitized user object (no token to client).
- `GET /api/auth/me` → returns current user from session or 401.
- `POST /api/auth/logout` → destroys session.
- Exports `requireAuth` middleware and `getJellyfin(req)` helper that returns
  `{ baseUrl, token, userId }` for downstream Jellyfin calls.

### 1.3 `server/jellyfin.js` *(new — not in handoff)* — Jellyfin REST client
- Thin wrapper around `fetch` that injects `X-Emby-Token`.
- Functions: `authenticate`, `getItems`, `getItemChildren`, `getImageUrl`,
  `buildHlsUrl(itemId, token)`, `syncPlay.*` (New/Join/Leave/SetNewQueue/
  Pause/Unpause/Seek/Ready/BufferingDone).
- Centralizes the **two corrected endpoints** so no caller hand-builds URLs.

### 1.4 `server/session.js` — party/session management
- Defines the `Session` model (§3) and a `SessionStore` (Map-backed).
- Pure logic, no socket coupling: `createSession`, `joinWaiting`,
  `approve`, `reject`, `kick`, `addGuest`, `removeGuest`, `transferHost`,
  `setLayout`, `setCollaborative`, `pushMessage`, `findByUser`.
- Host-disconnect grace timer logic lives here (§7).
- Emits via an injected callback so it stays testable without Socket.io.

### 1.5 `server/syncplay.js` — Jellyfin SyncPlay bridge
- On party create: calls `SyncPlay/New`, stores `syncPlayGroupId` on session.
- Maintains **one Jellyfin WS connection per active host token** (`/socket?api_key=`)
  to receive `SyncPlayCommand` / `SyncPlayGroupUpdate` / `SyncPlayUserJoined/Left`.
- Translates Jellyfin WS messages → Socket.io `sync:command` broadcasts to the
  party room.
- Exposes `play/pause/seek` that call the corrected REST endpoints, gated by
  permission checks (host or collaborative mode).
- Handles ticks↔seconds conversion (`seconds * 10_000_000`).

### 1.6 `server/livekit.js` — token minting
- `GET /api/livekit/token?partyId=` → verifies caller is an approved guest/host
  of that party, mints a LiveKit `AccessToken` with `identity = userId`,
  `roomJoin: true`, `room = partyId`. Returns `{ token, url }`.

### 1.7 Socket.io event handlers (in `index.js`, logic in `session.js`/`syncplay.js`)
Implements the full event map in §5. Every state-mutating event re-checks
permissions server-side (server is the sole authority).

---

## 2. Client Architecture

### 2.1 Routing / `App.jsx`
- Routes: `/login`, `/library`, `/party/:id`. Unauthenticated → `/login`.
- Wraps tree in `AuthContext` then `PartyContext`.
- (Router lib choice deferred — behavior: client-side routes, guarded by auth.)

### 2.2 Context
- **`AuthContext`** — holds `user`, `loading`; methods `login`, `logout`,
  `refresh` (calls `/api/auth/me` on mount). No token client-side (httpOnly).
- **`PartyContext`** — holds current `session` snapshot, `role` (host/guest/waiting),
  `layoutMode`, participants, chat messages; subscribes to Socket.io events and
  exposes action methods (create, join, approve, kick, sendMessage, etc.).

### 2.3 Hooks
- **`useSocket`** — singleton Socket.io client (with credentials), connection
  state, typed `emit`/`on` helpers, auto-reconnect.
- **`useSyncPlay`** — given a player ref: listens to `sync:command`, applies
  `play/pause/seek` to the Vidstack player, accounts for the `When` timestamp to
  align playback; reports `Ready`/`BufferingDone` back via socket → server →
  Jellyfin. Exposes host controls (`requestPlay`, `requestPause`, `requestSeek`).
- **`useLiveKit`** — fetches token from `/api/livekit/token`, connects to LiveKit
  room, publishes local cam/mic, exposes participant tracks. Handles
  connect/disconnect lifecycle.

### 2.4 Pages
- **`Login.jsx`** — Jellyfin username/password form → `AuthContext.login`. On
  success → `/library`. Shows error states.
- **`Library.jsx`** — fetches `/api/library/items`, renders grid (posters via
  `/api/library/image/:id`). Series → drill into seasons/episodes. "Start party"
  on an item → `party:create` → navigate to `/party/:id`.
- **`Lobby.jsx`** *(or merged into Party waiting state)* — guest's pre-approval
  screen while in `session.waiting[]`. Listens for `party:approved/rejected`.
- **`Party.jsx`** — the main room. Composes `Player`, `CameraGrid`/`Dock`, `Chat`,
  host-controls, `WaitingRoom` (host only). Reads `layoutMode` to pick float vs
  dock rendering path.

### 2.5 Components (behavior only — design TBD)
- **`Player.jsx`** — Vidstack `MediaPlayer` on the corrected HLS URL; wired to
  `useSyncPlay`. Host sees transport controls; guests' native controls are
  read-only unless collaborative mode.
- **`CameraGrid.jsx`** — float mode: maps participants → `<Rnd>` tiles over the
  video. Parent `position: relative`; video layer `pointer-events: none` so tile
  drags work (handoff gotcha).
- **`CameraTile.jsx`** — single participant's video+audio track, name label,
  per-tile controls (hide; host-only remove).
- **`Dock.jsx`** — dock mode: flex strip of tiles; video resizes to remaining space.
- **`Chat.jsx`** — message list + input; loads `chat:history` on mount, appends
  `chat:message` events.
- **`WaitingRoom.jsx`** — host-only panel listing `session.waiting[]` with
  approve/reject actions.

---

## 3. Data Model (in-memory, server)

```js
Session = {
  id,                    // party/room code
  hostId,                // jellyfin userId
  hostToken,             // jellyfin AccessToken (server-only, never sent to client)
  syncPlayGroupId,       // from SyncPlay/New
  mediaItemId,           // jellyfin item being watched
  mediaSourceId,         // required for HLS URL
  guests: [{ userId, name, socketId, joinedAt }],
  waiting: [{ userId, name, socketId }],
  messages: [{ userId, name, text, timestamp }],  // capped 200
  layoutMode,            // default 'float' (per-user override lives client-side)
  collaborativeControl,  // bool
  hostDisconnectTimer,   // NodeJS timer handle or null
}
```
Sessions persist until host closes or server restarts (no DB — out of scope).

---

## 4. Key Flows

### 4.1 Login
`Login form → POST /api/auth/login → Jellyfin AuthenticateByName → store token in
session + httpOnly cookie → client gets sanitized user → /library`.

### 4.2 Create party (host)
`Library pick → socket party:create {itemId} → server: resolve mediaSourceId,
SyncPlay/New, create Session, open Jellyfin WS bridge → host joins room →
party:state to host → navigate /party/:id`.

### 4.3 Join party (guest)
`Open /party/:id → socket party:join {id} → server validates auth →
session.waiting[] → emit party:waiting to host → (host approves) →
move to guests[], SyncPlay/Join under guest token, emit party:approved →
client fetches LiveKit token, connects player + cameras → party:state`.

### 4.4 Sync (host plays)
`Host hits play → socket sync:play → server permission check → SyncPlay Unpause →
Jellyfin WS pushes SyncPlayCommand → server broadcasts sync:command → all clients'
useSyncPlay applies play aligned to When timestamp`.

### 4.5 Cameras
`On approved → GET /api/livekit/token → connect LiveKit room=partyId → publish
cam/mic → useParticipants drives CameraGrid/Dock tiles`.

### 4.6 Chat
`socket chat:message {text} → server appends (cap 200) → broadcast chat:message;
on join server emits chat:history`.

---

## 5. Socket.io Event Contract

**Client → Server:** `party:create {mediaItemId}`, `party:join {partyId}`,
`party:approve {userId}`, `party:reject {userId}`, `party:kick {userId}`,
`party:transferHost {userId}`, `party:setCollaborative {bool}`,
`sync:play`, `sync:pause`, `sync:seek {positionTicks}`,
`sync:ready`, `sync:buffering`, `chat:message {text}`,
`camera:remove {userId}`, `layout:change {mode}`.

**Server → Client:** `party:state {session}`, `party:waiting {user}`,
`party:approved {}`, `party:rejected {}`, `party:kicked {userId}`,
`sync:command {type, data, when}`, `chat:message {msg}`, `chat:history {msgs}`,
`user:joined {user}`, `user:left {user}`, `camera:removed {userId}`,
`host:changed {hostId}`, `error {code, message}`.

(`camera:hide` and per-user `layoutMode` are client-local only — no server round trip.)

---

## 6. Permission Enforcement (server-side, every mutating event)

| Action | Allowed |
|---|---|
| play/pause | host, or any guest if `collaborativeControl` |
| seek | host only |
| kick / approve / reject | host only |
| camera:remove (others) | host only |
| transfer host / toggle collaborative | host only |
| chat | any approved member |

Server rejects unauthorized events with `error` and ignores the mutation.

---

## 7. Host Disconnect / Rejoin
`Host socket drops → start 30s timer + broadcast SyncPlay pause. Rejoin <30s →
cancel timer, restore. Timer fires → promote earliest-joined guest (transfer
SyncPlay ownership + hostToken handling), broadcast host:changed. Original host
returns later → joins as guest. Server always assigns host.`

---

## 8. Build Phases (maps to TODO.md)

| Phase | Deliverable | Exit check |
|---|---|---|
| 2 | Auth proxy + Login | login sets cookie, /me works |
| 3 | Library browser | real posters, pick item |
| 4 | Session + waiting room | join → waiting → approve |
| 5 | Player + SyncPlay bridge | host play/pause/seek mirrors to guest |
| 6 | LiveKit cameras | two tabs see each other |
| 7 | Chat | live + history |
| 8 | Dock layout | toggle persists |
| 9 | Host controls + disconnect | matrix holds, host handoff works |
| 10 | Polish + error states | reconnect, empty states |
| 11 | VPS deploy (tunnel + TURN) | cross-network sync + cameras |

---

## 9. Open Items Needing Your Input (design or decision)
- **Visual design / UX** for every page & component (you're bringing this).
- **Router library** (e.g. react-router) — behavior specified, lib TBD.
- **Who can host** — any Jellyfin user vs `IsAdministrator` only.
- **Styling approach** (CSS modules / Tailwind / etc.) — defer to design.
- **Series support depth** — movies-only first, or seasons/episodes in Phase 3?
- **LiveKit Cloud vs self-hosted** for production (local self-host already set up).
```
