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

---

# Active work (post-rebuild)

> Note: the sync engine was rebuilt as a host-authority shared-timeline engine
> (Phase 5 above is historical — no `syncplay.js`). Items below are the current
> queue.

## Phase 12 — HLS Sync Hardening
Adopt the buffer-aware corrections (senior review). Same code path in
`syncCore.js` / `useSyncPlay.js`. We are on HLS (expensive seeks), not
direct-play, so bands must be forgiving.
- [ ] **Buffer-aware hard-seek:** on a large correction, freeze the guest clock —
      `pause() → currentTime = predicted → await 'seeked' → wait ~1s buffered →
      re-read host live position once → play()`. Fixes the buffering chase loop
      in hopping mode (guest stalls while host clock advances → re-seeks → chases).
- [ ] **Widen the "seek in flight" guard:** `applyingRef` is only 150ms — too
      short for a real HLS seek+buffer. Hold suppression until `seeked` + buffered
      (single `isSeeking` flag shared with the buffer-aware routine).
- [ ] **Explicit drag start/end:** host emits "scrubbing → hold" on drag-start and
      one settled position on drag-end (today we only debounce 200ms).
- [ ] **HLS-tuned thresholds:** make the hard-seek band + buffer wait more forgiving
      for segment-fetch latency.
- [ ] **Testability:** extend the harness `VirtualPlayer` to simulate buffering
      stalls so the chase loop is regression-testable headlessly.
- **Verify:** harness scenario with simulated stalls converges (no re-seek loop);
      confirm live in a browser against Jellyfin.
- **DECISION PENDING — audio model** (separate job): mic picks up movie audio →
      echo. Pick auto-duck during playback / push-to-talk / AEC+headphones before
      building the AV control UX. (Recommended: auto-duck + optional PTT.)

## Phase 13 — Native media acquisition (Servarr, unified)
Make the download stack feel like ONE native catalog — the user must never see
that Radarr/Sonarr/Prowlarr/qBittorrent are separate services. Evolves the
current admin-ish `/discover` page into a seamless browse+get experience.
- [ ] **Unified Browse tab:** one catalog surface (Sen Player look) that searches
      and lists movies + series with poster, description, rating, year, runtime,
      genres — sourced from Radarr/Sonarr lookup behind the scenes.
- [ ] **Seamless owned-vs-available:** blend with the existing Jellyfin library so
      titles show as "in library / play" vs "available / download" in one view —
      no separate "downloader" mental model.
- [ ] **One-tap download:** a single "Download" action adds + monitors + triggers
      indexer search + sends to qBittorrent, with sensible default quality
      profile / root folder (no dialog friction for the common case).
- [ ] **Live status inline:** a downloading title shows progress on its own card
      and lands in the library when imported (build on Phase 5.3/5.4 monitor).
- [ ] Hide all service branding/config from the UI; keys/URLs stay server-side.
- **Verify:** search a movie not in the library → tap Download → it starts
      downloading and shows progress, then appears as playable once imported —
      without the user ever seeing "Radarr/Sonarr/qBittorrent".
