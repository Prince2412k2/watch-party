# Next session — prep

Two features to discuss and build. Everything below was read out of the tree
today, not recalled. `HANDOFF.md` still holds the operational detail (prod,
credentials, traps); this covers only the new work.

**Branch state:** `main` = `9516695` (PR #77, merged from `dev`). Everything from
the last session is on `main`; `main` and `dev` are level. Working tree clean.

---

## Feature A — delete the shared browser, stream directly on the client

### What exists today

The shared browser is a containerised Chromium that publishes its own screen
into the party's LiveKit room as a publish-only participant. It is **~4,700
lines** across five surfaces:

| Surface | Files |
|---|---|
| Container | `browser/` — Dockerfile, `agent.py`, `target_agent.py`, `network.py`, seccomp profile, `publisher/` (incl. a vendored `livekit-client.umd.js`) |
| Server | `app/server/browser/` — `agent.js`, `config.js`, `events.js`, `lease.js`, `policy.js`, + 2 test files |
| Web | `app/client/src/components/SharedBrowser.tsx` |
| Flutter | `models/shared_browser.dart`, `state/shared_browser_provider.dart`, plus call sites in `party_screen.dart`, `party_provider.dart`, `popcorn_control.dart` |
| Ops | 4 services + 3 networks + 3 volumes in **both** compose files, `docs/ops/shared-browser.md`, two specs |

Also carried: the `'browser'` party stage (`session.js:95`, `:331`), the
browser-control lease, and `BROWSER_*` env in `secrets/.env` on the VPS.

### Worth knowing before we start

**I added the browser stack to `docker-compose.prod.yml` yesterday** (`507f186`)
because it was configured but never deployed. If it is coming out, that commit
comes out with it — no harm done, but do not treat the prod compose as settled.
The `VPS_PUBLIC_IP` assertion added in the same commit is **unrelated and must
stay**; it is what catches coturn advertising an address the box does not own.

**The problem the browser was built to solve does not disappear with it.** Per
`docs/specs/2026-08-04-remote-browser.md`: *"A party can only watch what is in
the Jellyfin library. Anything else — a YouTube video, a clip someone linked in
chat, a livestream — means everybody opens it separately and tries to press play
at the same time."* Direct client streaming has to answer that, or we are
choosing to drop the use case.

### Questions to settle first

1. **What does "direct streaming on the client" mean?** Two very different
   readings: (a) each client fetches the *same external source* itself and we
   sync playback through the existing sync engine — cheap, sharp, no server
   media path; or (b) something closer to the current model but without the
   container. The answer changes the entire scope.
2. **If (a): what plays the source?** An embedded webview per client, or a
   direct media URL into the existing player? A webview brings back most of what
   the container was avoiding — cookies, DRM, per-site breakage — just moved to
   every client instead of one.
3. **DRM.** The container never handled Widevine either, so this is not a
   regression, but it decides whether "anything else" means YouTube or means
   Netflix.
4. **Is the removal staged or atomic?** The stage, the lease and the party
   protocol are load-bearing; ripping all five surfaces in one commit is a large
   blast radius on a system with a live prod deploy.

---

## Feature B — rooms and mirroring

### The UX complaint, restated

Rooms read as a hybrid of Google Meet and a video call. Starting one is
ceremonious. It should be **single-user friendly, with a room startable at any
moment** — closer to "I am already in a room, others may join" than "convene a
meeting".

### The important discovery

**Semantic mirroring already exists, on the web client only.** Not screen
sharing — state replication:

```
app/server/index.js
  browse:navigate   the driver moved through the library  → mirrored to the room
  browse:view       tab / screen / mediaId / seasonId / episodeId
  browse:pointer    live scroll fraction + cursor x,y      → relay-only, ephemeral
app/client/src/mirror.ts
  module-level pub/sub, applied imperatively in one rAF loop
```

`mirror.ts` is explicit about why: *"The host's scroll position + cursor is
high-frequency (30–60 fps). Routing it through React state would re-render the
whole library on every frame."* Scroll is a **0..1 fraction of scrollable
height**, and cursor x/y are **fractions of the shared pane's bounding rect, not
the viewport** — deliberately viewport-independent, so it maps across different
screen sizes. That is precisely the "adjusting scale" problem, already solved
once.

**Flutter has none of it.** No mirror store, no `browse:pointer` handling. So
today the feature is web-to-web only, and the native app — the one being
actively developed — cannot participate.

### The fork to decide

| | Pixel mirroring (screen share) | Semantic mirroring (what exists) |
|---|---|---|
| Fidelity | Exactly the host's screen, any app | Only surfaces both clients implement |
| Bandwidth | A video stream per room | A few hundred bytes/sec |
| Sharpness | Re-encoded, scaled, soft text | Native rendering at each viewer's DPI |
| Scale mismatch | Letterboxed or cropped | Fractions map across sizes |
| Cost to build | LiveKit screen-share track + a viewer | Port `mirror.ts` to Dart + wire the rail |

"Whole screen is mirrored, adjusting scale, where they're scrolling, where
they're clicking" describes the *experience* of both. Which one we mean changes
everything, and it is the first thing to settle.

My read, for what it is worth: semantic mirroring is the better product here —
sharp text, trivial bandwidth, and it already half-exists — **unless** the intent
is to mirror things outside our own UI, in which case only pixels will do. That
also interacts with Feature A: if direct streaming means an embedded webview, a
webview is exactly the surface semantic mirroring cannot reach.

### Existing pieces that will be touched

- `partyAuthority.ts` / `browseAuthority.ts` — who may drive (`canDrive` =
  host **or** `collaborativeControl`).
- Party stages `lobby` / `watching` / `browser` — a room that is "always on"
  may not want a lobby stage at all.
- `analog/surface.ts`, `browseCore.ts`, `focus_memory.dart` — the shared browse
  model both clients render from; the natural mirroring boundary.
- `party_provider.dart` + `socket_client.dart` — where Flutter would join.

---

## Carried-over context

**Do not re-litigate these** (all verified last session):

- `main` is deployed by CI on push, via `deploy/up-prod.sh`. Do not edit compose
  on the box; the deploy does `git pull --ff-only`.
- The PAT is read-only. The user pushes and merges.
- `flutter` only runs in a Herdr pane, and a fresh pane starts at the repo root
  where `flutter analyze` reports a false `No issues found!`. Set the pane cwd as
  its own command first. Write verification to a file with a `DONE` marker;
  never read it off the terminal mid-write.
- Baseline: **Flutter 432, server 151, web 430**, `tsc --noEmit` clean.

**Known-open, unrelated to these features:**

- The profile avatar's red dot is hardcoded — renders unconditionally, driven by
  nothing.
- Sonarr per-season/episode download actions are still missing from a library
  show's detail page (deliberate regression from the Shows merge).
- Issues #66 / #67 remain open and unaudited; #65 is blocked on them; #68
  (`party:leave`) is genuinely unimplemented — `grep` finds no handler.
- The watch-party control panel has no widget test; nothing catches a guest
  being shown a host-only action.
