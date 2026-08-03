# Web client polish + PWA — discovery brief

Status: plausibility discussion (pre-spec). Brownfield — most product/user/domain
context inherited from existing project work, not re-interviewed.

## Synthesis

**Product.** `watch_party` is a self-hosted watch-party app for a small friend group
(Jellyfin + Sonarr/Radarr backend, Flutter desktop/mobile app, React/Vite web client).
This request is a refinement of the existing web client, not a new product: (1) general
visual polish, (2) make the web client a real installable PWA, (3) a fullscreen movie
view with a floating/popup overlay of party members' camera video, (4) browser-side
video caching so a watched file doesn't need to be re-fetched to rewatch.

**Users.** Same existing friend group already using the app. Primary device target for
this request is explicitly **iOS Safari / iPhone** — confirmed as the *main* target,
not an edge case. Desktop/Android also used but iOS is load-bearing for feasibility.

**Reuse scope (feature 4).** User wants both in-session reuse (no re-fetch on
scrub/rejoin) *and* true persistent offline download — persistent download is the real
goal, in-session reuse is a lesser included case.

**Existing groundwork found in repo (not assumed — read directly):**
- `app/client/public/manifest.webmanifest` + `index.html` already have full PWA install
  metadata (icons, standalone display, apple-mobile-web-app meta tags). No service
  worker exists anywhere in the codebase yet — nothing is actually cached or
  installable-offline today, only "installable as a shortcut."
- `Party.tsx` already has a real fullscreen system with an explicit iOS fallback path
  (`document.fullscreenEnabled` is false on iPhone Safari, so there's a "CSS faux-fullscreen"
  branch — comment marks it "Phase B"), plus an existing `CameraTile` component rendering
  participants during a call. Feature 3 (fullscreen + floating camera popup) is mostly
  UX refinement of something that already exists, not new infrastructure.
- Playback runs through `hls.js` driving a hand-built sync engine (`syncCore.ts`,
  `bufferSeek.ts`) that manipulates HLS buffering directly for tight party-sync. No
  static/direct-play/download route exists server-side yet — everything currently goes
  through the transcoding HLS proxy.

## Raw

> "my motivation is to have a fullscreen movie view with pop up screen of people. also
> video caching/downloading via browser and reusing it."

> "IOS is our main target" (device mix)

> "Both, but persistent is the real goal" (reuse scope)

## Risks / landmines

- The custom HLS sync engine is finely tuned (buffer manipulation for tight sync) and is
  the thing most likely to break if a caching layer is bolted on without a distinct
  "playing from local copy" code path.
- This session just lived through a production regression from a security-hardening
  merge (LiveKit upgrade gate) that looked correct in isolated testing but broke real
  clients — a reminder that "works in a synthetic test" isn't proof for this codebase.
- iOS Safari's Service Worker fetch interception has known historical unreliability for
  `<video>`-element-initiated network requests (especially ranged HLS segment fetches),
  which is why passive "let the browser's own fetches get cached" is not assumed to work
  for iOS — see plausibility discussion in-thread.

## Later (explicitly deferred, not in scope now)

- Full visual redesign of every page (Library/Discover/Downloads) — not yet confirmed
  as in scope; today's ask is fullscreen/PiP + PWA + caching specifically.
- DRM/licensing concerns — moot, this is a personal Jellyfin library with no protected
  content.

## Update — phone UI density (2026-08-03)

Sequencing set by user: (1) reduce clutter/density on the web client's phone view,
inspired by the existing web/desktop design language, (2) run the iOS PWA storage
plausibility spike, (3) if plausible, build persistent download + a separate cache
management tab (per-title storage size, "download fully" / "remove entirely").

Confirmed target surface: `app/client`'s mobile/responsive view (not `flutter_app`).
Confirmed pain point: visual density/clutter, not navigation structure or a specific
screen.

**Root cause found by reading the code (not assumed):** there IS a dedicated phone
shell (`.mobile-shell`/`.mobile-screen`/`MobileApp`, `pointer: coarse` gating, dvh-aware,
momentum scroll, press-not-hover) — real engineering effort went into phone
presentation already. But the actual page content (`Library.tsx`, `Downloads.tsx`,
`FindDownload.tsx`, `Party.tsx`) is desktop's layout parameterized by a `mobile` boolean
that mostly just turns down numbers — `mobile ? 12 : 18` gaps, `mobile ? 150 : 200`
card widths, same grid density, same multi-field modals shrunk to fit rather than
restructured. That's the actual source of "clunky/dense": phone gets the desktop
information layout at smaller scale, not a phone-native one.

Proposed direction: fewer simultaneous elements per screen, dense multi-field modals
(release pickers, manual-source dialogs) become full-screen step sheets instead of
shrunk stacked forms, larger consistent spacing rhythm, cut redundant chips/labels.

## Exit

Handing back to the user for a direction decision. Once a direction is chosen, the two
features have very different next steps:
- Feature 3 (fullscreen + camera popup) — small enough for `quick-spec` directly.
- Feature 4 (persistent offline download, iOS-first) — recommend a narrow technical
  spike before spec'ing the full feature, per the plausibility discussion.
