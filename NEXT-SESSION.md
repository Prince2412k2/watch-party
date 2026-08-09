# Next session — prep

Feature A is done; Feature B is the live work. Everything below was read out of
the tree, not recalled. `HANDOFF.md` still holds the operational detail (prod,
credentials, traps); this covers only the new work.

**Branch state:** the browser removal is on `feat/youtube-replaces-browser`,
branched from `main` at `1fa45b6`. Not merged, not pushed.

---

## Feature A — delete the shared browser ✅ DONE

Removed on `feat/youtube-replaces-browser`. ~6,000 lines: the container, the
server module and lease table, both clients, both compose files, the `'browser'`
party stage, the docs and the two specs. Spec:
`docs/specs/2026-08-09-remove-shared-browser.md`.

**No replacement was built.** A YouTube implementation was specified in detail
and then deliberately set aside — the first revision of that spec file still has
it (`git log --follow`), including the finding that `youtube.com` cannot be
iframed at all (`X-Frame-Options: SAMEORIGIN`; only `/embed/<id>` is embeddable),
and that `3rd-party/howardchung-watchparty` solves this with a server-side Data
API proxy plus a native search UI rather than an embedded browser. Worth reading
before anyone proposes shared external content again.

**What survived on purpose:** `mirror.ts`, `browse:navigate`, `browse:view`,
`browse:pointer`, `partyAuthority.ts` and `browseCore.ts`. They look
browser-adjacent and are not — see Feature B.

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
