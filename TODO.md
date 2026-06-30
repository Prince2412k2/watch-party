# Watchparty — Build TODO (Start → End)

Local-dev-first. Coturn/TURN deferred until VPS deploy. Each phase ends with a
concrete "verify" so we never build on an unproven base.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done

---

## Phase 0 — Repo & Tooling Scaffold
- [ ] `git init` + `.gitignore` (node_modules, .env, jellyfin/config, media)
- [ ] Create directory tree (`app/server`, `app/client`, config files)
- [ ] Root `docker-compose.yml` (Jellyfin + LiveKit; Coturn commented out)
- [ ] `livekit.yaml` (dev keys, localhost)
- [ ] `.env.example` + local `.env`
- [ ] `app/package.json` (server deps), `app/client/package.json` (client deps)
- **Verify:** tree matches handoff; compose file parses (`docker compose config`)

## Phase 1 — Services Up
- [ ] `docker compose up` — Jellyfin + LiveKit running
- [ ] Jellyfin setup wizard → create admin user
- [ ] Drop 1-2 sample video files into `./media`, add as a Library
- [ ] Confirm Jellyfin reachable at `:8096`, LiveKit ws at `:7880`
- **Verify (risk check):** manually hit `POST /SyncPlay/New` with a token →
  returns a GroupId. Mint a LiveKit token via SDK → connects.

## Phase 2 — Auth
- [ ] `server/index.js` — Express + Socket.io entry
- [ ] `server/auth.js` — proxy `POST /Users/AuthenticateByName` to Jellyfin
- [ ] `/api/auth/login` → store AccessToken in httpOnly cookie
- [ ] `/api/auth/me` + logout; auth middleware for protected routes
- [ ] Client `AuthContext` + `Login.jsx`
- **Verify:** log in with Jellyfin creds, cookie set, `/me` returns user

## Phase 3 — Library Browser
- [ ] Server proxy: `GET /Items` (Movies/Series), `/Children`, poster images
- [ ] `Library.jsx` — poster grid, pick media
- **Verify:** browse real Jellyfin library, see posters, select an item

## Phase 4 — Party Session + Waiting Room
- [ ] `server/session.js` — in-memory session model (id, host, guests, waiting)
- [ ] Socket.io: `party:create`, `party:join`, approve/reject/kick
- [ ] Waiting-room flow + host approval events
- [ ] `PartyContext`, `Lobby.jsx`, `WaitingRoom.jsx`
- **Verify:** host creates party, 2nd tab joins → lands in waiting → host approves

## Phase 5 — Video Player + SyncPlay
- [ ] `server/syncplay.js` — bridge Jellyfin SyncPlay REST + WS events
- [ ] Forward Jellyfin WS (`SyncPlayCommand` etc.) → Socket.io rooms
- [ ] `Player.jsx` — Vidstack on Jellyfin HLS url
- [ ] `useSyncPlay.js` — apply commands; report Ready/BufferingDone
- [ ] Ticks↔seconds conversion helper
- **Verify:** host play/pause/seek mirrors in guest tab within ~1s

## Phase 6 — LiveKit Cameras
- [ ] `server/livekit.js` + `/api/livekit/token`
- [ ] `useLiveKit.js` — connect, publish cam/mic
- [ ] `CameraTile.jsx`, `CameraGrid.jsx` (react-rnd floating tiles)
- [ ] Hide (local) vs remove (host broadcast) logic
- **Verify:** 2 tabs see each other's camera in draggable/resizable tiles

## Phase 7 — Chat
- [ ] Server message buffer (max 200) + history on join
- [ ] `Chat.jsx` sidebar
- **Verify:** messages broadcast live + history loads on join

## Phase 8 — Dock Layout Mode
- [ ] `Dock.jsx` — flex strip layout; video resizes
- [ ] `layoutMode` toggle, persist per-user in localStorage
- **Verify:** toggle float↔dock, preference survives reload

## Phase 9 — Host Controls UI
- [ ] Kick, approve, transfer host, collaborative-mode toggle
- [ ] Enforce permissions server-side (server is authority)
- [ ] Host disconnect → 30s grace → promote first guest
- **Verify:** permission matrix from handoff holds; host handoff works

## Phase 10 — Polish
- [ ] Transitions, error/empty states, reconnect handling
- [ ] Basic responsive layout
- [ ] README / run instructions

## Phase 11 — VPS Deploy (when ready for remote guests)
- [ ] Provision VPS w/ public IP; open ports (8096, 7880/7881, 3478, 50000-50020/udp, 3000)
- [ ] Enable + configure Coturn (`network_mode: host`, real creds)
- [ ] Real LIVEKIT keys + TURN_URL pointing at public IP
- [ ] Reverse proxy w/ WS upgrade headers (SyncPlay needs this)
- [ ] HTTPS (cameras require secure context off-localhost)
- **Verify:** two people on different networks watch in sync w/ cameras
