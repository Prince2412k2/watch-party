# Phone UI/UX Plan — Watch Screen

**Scope:** Phone behaviour of the watch-party watch screen, now that the app is
exposed over HTTPS via Tailscale Funnel (`https://dsk-4161.tail0a3558.ts.net`)
and a real iPhone is on the tailnet. Headline deliverable: a correct, per-platform
**fullscreen + orientation** story that replaces the fragile CSS-rotate hack.

**Ground rules for whoever executes this:** planning doc only. No app source was
changed to produce it. Steps below are sized for one subagent each.

Files in play:
- `app/client/src/pages/Party.jsx` — `WatchView`, `LandscapePhone`/`usePortraitPhone`, `MobileCameraStrip`, `ChatSheet`, tap-to-toggle control layer, fullscreen owner (`isFs`, `toggleFullscreen`, `fullscreenchange`).
- `app/client/src/components/Player.jsx` — `ELEMENT_FS_SUPPORTED`, `runFullscreen`, `useIosVideoFullscreen`, `MobileBottomBar`/`BarBtn`, `AVControls`, `TimelineControls`, `SyncBridge` key handler.
- `app/client/src/hooks/useIsMobile.js` — `useIsMobile`, `usePhone`.
- `app/client/src/watchLayers.js` — `Z` scale.
- `app/client/src/styles.css` — `--sa-*` safe-area vars, keyframes.
- `app/client/index.html` — `viewport-fit=cover`.

---

## 1. Audit findings

### 1a. Fullscreen (headline)

**F1 — On iPhone Safari, fullscreen always drops the whole party.**
`ELEMENT_FS_SUPPORTED = !!document.fullscreenEnabled` (Player.jsx:20). On **iPhone
Safari this is `false`** (only iPad Safari and Android Chromium report `true`).
`runFullscreen` (Player.jsx:37-45) therefore always takes the
`v.webkitEnterFullscreen()` branch on iPhone → **native video fullscreen that
hides every React overlay**: camera strip, chat, mic/cam controls, room code, host
badge. The one platform we now actually test on (the iPhone over Funnel) is the
one that loses all "party" chrome the moment someone taps fullscreen. This is the
core problem to solve. It also silently means the "fullscreen" button does two
completely different things depending on device, with no shared mental model.

**F2 — No orientation lock anywhere; "fullscreen" on a portrait phone is just a
letterboxed portrait video.** `toggleFullscreen` (Party.jsx:193-197) calls
`el.requestFullscreen()` only. There is no `screen.orientation.lock('landscape')`.
On Android Chromium a user in portrait who taps fullscreen gets a portrait
fullscreen with a thin letterboxed 16:9 strip in the middle — the worst of both
worlds. Rule hit: `orientation-support` (layout must be operable/optimal in
landscape) is unmet because we never *drive* the phone into landscape.

**F3 — The `LandscapePhone` CSS-rotate hack is applied to the LOBBY only, not the
watch screen.** Contrary to the brief's assumption, `WatchView` (Party.jsx:130) is
**not** wrapped in `LandscapePhone`; only the lobby `Library` view is
(Party.jsx:104). Consequences:
- The watch screen has **no forced-landscape and no "rotate your phone" hint at
  all** — a portrait viewer just sees a small letterboxed movie and the bottom bar,
  with no guidance. That is the real regression to fix, and it is a *content-first*
  failure (`content-priority`, `visual-hierarchy`): the movie, the primary content,
  is tiny while chrome dominates.
- The `transform: rotate(90deg)` hack that *does* run (lobby) is fundamentally
  broken w.r.t. two things: (a) **safe-area insets do not rotate** —
  `env(safe-area-inset-*)` always refer to the physical device edges, so after a
  90° rotate every `--sa-*`-based inset points the wrong way (top padding protects
  a side edge); (b) it is incompatible with the real Fullscreen API and native
  orientation — you cannot combine a rotate-transform faux-landscape with
  `requestFullscreen()` + `orientation.lock()` without them fighting. Rule hit:
  `safe-area-awareness`, `standard-gestures`/`system-gestures` (a rotated coordinate
  space confuses swipe-back and the home indicator).

**F4 — `isFs` state only ever tracks the element-fullscreen path.** Party.jsx:187-191
listens for `fullscreenchange` and sets `isFs` from `document.fullscreenElement`.
On iPhone (no element FS) `isFs` is permanently `false`; the button icon relies on
`useIosVideoFullscreen`'s `iosFs` instead (Player.jsx:544/587). Two parallel truth
sources, only reconciled inside the button components — brittle, and there is no
single "are we immersive?" state the rest of `WatchView` can react to (e.g. to
change layout, force landscape, or re-poke the control layer).

**F5 — Auto-enter/auto-exit UX is undefined.** Fullscreen is purely manual (a button
/ `f` / Ctrl+F). Entering FS does not `poke()` the control layer, and exiting FS
(Android back gesture, iOS Done button, Esc) is only observed on desktop via
`fullscreenchange`; on iOS the `webkitendfullscreen` event is handled locally in the
button but nothing else in `WatchView` knows we left. There is no orientation
*unlock* on exit either (once we add lock).

**F6 — iOS Safari bottom-toolbar can overlap the bottom control bar.** Because iOS
has no element FS, the watch screen renders inside normal Safari chrome.
`MobileBottomBar` is pinned at `bottom: calc(var(--sa-b) + 8px)` (Player.jsx:608).
`--sa-b` accounts for the home indicator but **not** Safari's dynamic bottom
toolbar, which can sit on top of the bar until the user scrolls (and this is a
`position:fixed; inset:0` page that doesn't scroll, so the toolbar may never
retract). Rule hit: `fixed-element-offset`, `safe-area-awareness`.

### 1b. General phone watch-screen UX

**G1 — `100vh`/`inset:0` vs iOS dynamic viewport.** Root is `position:fixed; inset:0`
(Party.jsx:201). `html,body,#root { height:100% }` (styles.css:29-37). On iOS this
tracks the *layout* viewport and can leave content under the URL/toolbar in the
non-FS case. Prefer `100dvh`/`min-h-dvh` semantics for the stage height. Rule:
`viewport-units`.

**G2 — Control bar is dense for a short landscape phone.** `MobileBottomBar` packs up
to 8 targets (transport, mic, talk, cam, hide-self, camera-strip, settings,
fullscreen). Each is a compliant 44×44 with 8px gaps (good — `touch-target-size`,
`touch-spacing`), but on a 740×360 phone in landscape the middle cluster is
`overflowX:auto` and can clip/scroll, which is a poor discoverability signal and
risks hiding fullscreen behind a scroll. Rule: `overflow-menu` (prefer a "more"
menu over cramming), `no-precision-required`.

**G3 — Tap model is single-purpose and slightly surprising.** `onSurfaceTap`
(Party.jsx:182-185): on phone a tap *hides* chrome if visible, else *shows* it.
There is no **double-tap-to-seek** (±10s) and no **long-press** affordance, both of
which phone users now expect from a video surface. Also, taps on the video toggle
chrome even for guests who can't scrub, which is fine, but there's no visual "tap
target" feedback (`press-feedback`, `tap-feedback-speed`).

**G4 — Camera strip / chat sheet coexistence with the bar is close but untested at
real landscape sizes.** `MobileCameraStrip` sits at `bottom: sa-b + 72px` when
chrome is visible (Party.jsx:309) assuming a ~56px bar; the bar's real height is
`44 + 12` padding ≈ 56 so 72 is a thin 16px clearance — acceptable but fragile if
the bar wraps. `ChatSheet` is a right slide-over `width: min(340, 100vw - insets)`;
on a 390px-tall landscape phone that's fine, but the sheet + camera strip + bar can
stack in the bottom-right corner. Needs a real-device pass (`scroll-behavior`,
`fixed-element-offset`).

**G5 — Contrast of inactive glass buttons over bright video.** Inactive `BarBtn`
background is `rgba(255,255,255,.08)` with white icons (Player.jsx:688). Over a
bright movie frame the icon-to-immediate-background contrast can dip below 3:1
(`icon-contrast`, `contrast-data`). The glass bar behind helps but the per-button
fill is weak. Consider a slightly stronger idle fill or a scrim gradient behind the
bar.

**G6 — Reduced-motion not honoured.** Keyframes (`sheetIn`, `scrimIn`, `up`, `spin`,
`edgeRipple`) run unconditionally; no `@media (prefers-reduced-motion: reduce)`
block exists in styles.css. Rule: `reduced-motion`.

**G7 — Portrait watch experience has no guidance.** Tied to F3: a phone held in
portrait on the watch screen gets a letterboxed movie and no prompt to rotate and
no auto-landscape. First-run phone users will think it's broken.

---

## 2. Fullscreen fix design

### 2.1 Principle

Introduce **one** owner concept in `WatchView`: an `immersive` state (are we in the
app's fullscreen presentation?) that is *derived from whichever mechanism the
platform actually supports*, plus an explicit `enterImmersive()` / `exitImmersive()`
pair that branches by capability. The button icon, the control-layer poke, the
orientation lock, and layout all read this single state. Kill `LandscapePhone` for
the watch path entirely and never use it there.

### 2.2 Per-platform matrix

| | **Android / Chromium phone** | **iPhone Safari** | **iPad Safari** | **Desktop (unchanged)** |
|---|---|---|---|---|
| Element FS API | `document.fullscreenEnabled === true` | **false** | true | true |
| Enter | `container.requestFullscreen()` → then `screen.orientation.lock('landscape')` (allowed only while FS) | **CSS faux-fullscreen**: set `immersive` flag, page is already `fixed inset:0`; hide URL bar as far as possible; show rotate hint if portrait | `container.requestFullscreen()`; `orientation.lock` best-effort (may reject → ignore) | `container.requestFullscreen()` |
| Overlays kept? | **Yes** (element FS keeps React overlays) | **Yes** (faux-FS keeps overlays) | Yes | Yes |
| Orientation | Locked landscape while immersive | Cannot lock; rely on device rotation + rotate hint | Best-effort lock, else free | n/a |
| Exit | `document.exitFullscreen()` (also Android back gesture); `orientation.unlock()` on exit | Clear `immersive` flag; unlock n/a | `exitFullscreen()` + `unlock()` | `exitFullscreen()` |
| State source | `fullscreenchange` → `document.fullscreenElement` | our `immersive` flag | `fullscreenchange` | `fullscreenchange` |

**Decision on iOS strategy: CSS faux-fullscreen, NOT native video FS.**
Rationale: the entire product value is watching *together* — chat, cameras,
push-to-talk, host controls. `webkitEnterFullscreen()` throws all of that away
(F1). A faux-fullscreen (the page is already `position:fixed; inset:0`) keeps every
overlay, keeps our control layer, and is the only way to preserve the party on
iPhone. We accept that iPhone Safari cannot hide its own top/bottom browser chrome
programmatically — we mitigate with `viewport-fit=cover`, `100dvh` sizing, and
correct safe-area insets so nothing is *occluded*, and we keep the rotate hint so
the user turns the phone for a near-full-bleed 16:9. Keep the native
`webkitEnterFullscreen` path available **only** as an explicit, secondary "expand
video only" affordance if we ever want a chrome-free movie — but it is not the
default fullscreen button on iPhone anymore.

> iOS PWA / standalone note: if the app is added to the Home Screen
> (`display: standalone`), Safari's URL/toolbar disappear and faux-fullscreen
> becomes effectively true fullscreen. Worth advertising ("Add to Home Screen for
> full-screen") but not required. `apple-mobile-web-app-capable` can be added later;
> it does not block this plan.

### 2.3 Fate of `LandscapePhone` / the rotate hack

- **Remove `LandscapePhone` from the watch path** (it was never there — keep it out).
- **Replace the `transform: rotate(90deg)` mechanism** with a **`RotateHint`
  overlay** that does NOT rotate the DOM. It only *detects* portrait
  (`orientation: portrait` + coarse pointer) and shows a dismissible, centered
  "Rotate your phone for the best view" chip. No coordinate-space rotation → safe
  areas, gestures, and fullscreen all behave normally.
- For the **lobby** (where `LandscapePhone` currently lives): also retire the rotate
  transform there and use the same non-rotating `RotateHint`. The library grid can
  simply reflow for portrait. (Lower priority; can be a follow-up step — see Phase
  D. It is the same broken safe-area/gesture story, just less visible.)

### 2.4 Orientation strategy

- **Android/Chromium:** on `enterImmersive`, after `requestFullscreen()` resolves,
  call `screen.orientation.lock('landscape').catch(()=>{})`. Lock is spec-gated on
  being in fullscreen, so order matters. On `exitImmersive` call
  `screen.orientation.unlock()`.
- **iPhone:** `screen.orientation.lock` is unsupported/throws → swallow. Show
  `RotateHint` while portrait; hide it in landscape.
- **iPad / desktop:** best-effort lock, ignore rejection.
- Never rotate the DOM. Never assume lock succeeded — always keep the rotate hint as
  the graceful-degradation path.

### 2.5 Entry / exit UX

- **Do NOT auto-enter on play.** Auto-fullscreen without a user gesture is blocked by
  browsers anyway and is jarring. Instead: **fullscreen is a one-tap explicit
  action**, and we make it obvious (a prominent FS button, plus tapping the movie
  once shows chrome that includes it). Optionally, **offer** auto-immersive on the
  *first* host "play" via a non-blocking toast ("Tap for full screen") — deferred,
  not in the core steps.
- **Entering** immersive: set state, run platform branch, lock orientation, and
  `poke()` the control layer so the user sees controls settle then auto-hide.
- **Exiting**: any of exitFullscreen button / Esc / Android back / iOS "done"
  (native path) / our faux-FS toggle. All funnel through the single `immersive`
  state via `fullscreenchange` (element paths) or our own setter (iOS faux). On
  exit, unlock orientation.
- **Button icon**: reads the single derived `immersive` state (not two separate
  `isFs`/`iosFs`). Enter icon (expand) ↔ exit icon (compress) consistently on all
  platforms.

### 2.6 State tracking (concrete)

In `WatchView`:
```
const immersive        // single source of truth
enterImmersive()       // branch: element FS + lock  |  iOS faux flag
exitImmersive()        // branch: exitFullscreen + unlock | clear flag
// fullscreenchange listener updates `immersive` for element-FS platforms
// iOS faux path updates `immersive` directly
```
Pass `immersive` + `enterImmersive`/`exitImmersive` down to `Player`. Delete the
device-branching `runFullscreen`/`ELEMENT_FS_SUPPORTED`/`useIosVideoFullscreen`
duplication in the button components; they just call the callbacks and render from
`immersive`.

### 2.7 Fallbacks / graceful degradation

1. `requestFullscreen` rejects (e.g. iframe policy) → fall back to faux-FS flag so
   the container still fills and overlays stay.
2. `orientation.lock` rejects/absent → keep rotate hint; do nothing else.
3. `screen.orientation` absent entirely → rotate hint only.
4. Reduced-motion → skip enter/exit scale/slide, just crossfade.

---

## 3. Phone watch-screen UX plan

Target sizes: **844×390** and **740×360** landscape (iPhone/mid Android), and the
degraded **portrait** case (≤430 wide).

### 3.1 Layout (landscape, immersive)

- Movie is full-bleed `object-fit: contain` on black (keep). At 16:9 on 844×390 the
  movie nearly fills; small pillar/letterbox bars are fine and are where chrome
  lives so it never covers picture.
- **Top-left:** room code + count chip (keep, RoomControls.jsx:66). **Top-right:**
  chat, host, leave cluster (keep). Both fade with `visible`. Ensure they clear
  `--sa-l`/`--sa-r` (they do).
- **Bottom:** single glass `MobileBottomBar` (keep the consolidation — it's good),
  but **split into primary + overflow** for short phones (see 3.2).
- **Camera strip:** keep collapsible bottom strip; keep default-collapsed so it never
  covers picture (good, `content-priority`). Verify 16px clearance above the bar at
  real sizes; make the clearance derive from the actual bar height via a CSS var
  rather than the hard-coded 72px.
- **Chat:** keep right slide-over sheet + scrim (good — dismissible, `modal-escape`).
  Confirm sheet width leaves the movie visible on 740-wide (it does: 340 max).

### 3.2 Control layer

- **Keep** auto-hide-on-idle (3s) + tap-to-toggle. **Add** `poke()` on immersive
  enter and on orientation change.
- **Primary cluster (always visible in bar):** play/pause (or lock glyph for
  guests), mic, camera, fullscreen. **Overflow "more" (⋯) button** opens a small
  glass popover for: push-to-talk, hide-self, camera-strip toggle, settings/quality.
  This fixes G2 (no horizontal scroll / clipped fullscreen) and satisfies
  `overflow-menu`. On roomy 844-wide phones the overflow can inline; gate by width.
- Fullscreen button must **never** be inside the scrolling/overflow region — it's a
  primary action (`primary-action`).
- Strengthen idle button fill from `.08` toward `~.14`, or add a subtle
  bottom scrim gradient behind the bar, to hold ≥3:1 icon contrast over bright
  frames (G5, `icon-contrast`).

### 3.3 Gestures

- **Single tap:** toggle chrome (keep).
- **Double-tap left / right third:** seek −10s / +10s (controllers only; show a brief
  ripple + "−10s" label). Guests get chrome toggle only. Add a movement threshold so
  a tap isn't misread (`drag-threshold`, `standard-gestures`).
- **Long-press anywhere (controllers):** optional 2× speed while held — deferred,
  nice-to-have.
- Do not attach horizontal swipe to the movie surface (would fight iOS back-swipe /
  system gestures — `system-gestures`, `gesture-conflicts`).
- Every gesture has a visible-control equivalent (`gesture-alternative`): seek via
  the timeline, chrome via the bar.

### 3.4 Safe areas, viewport, motion

- Keep `--sa-*` usage on all fixed chrome. **Add** an iOS bottom-toolbar cushion: use
  `min-height: 100dvh` semantics for the stage and, for the bottom bar, bump the
  offset to `calc(var(--sa-b) + 8px)` **plus** rely on `dvh` so the bar rides above
  Safari's toolbar (F6, G1).
- Add a `@media (prefers-reduced-motion: reduce)` block in styles.css disabling
  `sheetIn`/`scrimIn`/`edgeRipple`/`up` (fade only), and pausing decorative pulses
  (G6, `reduced-motion`).

### 3.5 Keep vs change (Phase 3.1 legacy)

**Keep:** consolidated bottom bar, 44px targets + 8px gaps, collapsible camera strip,
dismissible chat sheet + scrim, safe-area vars, guest lock glyph, PTT press-and-hold.
**Change:** fullscreen mechanism (§2), add rotate hint (non-rotating), add
overflow menu for short phones, add double-tap seek, reduced-motion, bottom-toolbar
cushion, stronger idle contrast, single `immersive` state.

---

## 4. Phased implementation steps (subagent-sized)

Each step is independently dispatchable; ordered by priority (fullscreen first).

### Phase A — Single immersive state + Android/Chromium correctness
**Scope:** In `WatchView`, replace `isFs`/`toggleFullscreen` with `immersive`,
`enterImmersive`, `exitImmersive`. Element-FS platforms: `requestFullscreen()` then
`screen.orientation.lock('landscape')`; on exit `exitFullscreen()` +
`orientation.unlock()`. Keep the `fullscreenchange` listener as the state source.
`poke()` on enter and on `orientationchange`. Pass the new props to `Player`;
simplify the FS button to read `immersive` and call the callbacks.
**Files:** `Party.jsx`, `Player.jsx`.
**Acceptance:** Android Chrome phone in portrait taps FS → goes true fullscreen AND
rotates to landscape with all overlays (cameras/chat/controls) visible; exit returns
to portrait, overlays intact. Desktop unchanged. Icon reflects state on all paths.
**Device-only verification:** orientation lock (desktop can't confirm).

### Phase B — iOS faux-fullscreen (keep the party)
**Scope:** On iPhone Safari (`!document.fullscreenEnabled`), `enterImmersive` sets the
`immersive` flag (page already `fixed inset:0`) instead of calling
`webkitEnterFullscreen()`. Overlays stay. Demote native video FS to a non-default
"video only" option (or drop for now). Reconcile the button to the single state.
**Files:** `Player.jsx`, `Party.jsx`.
**Acceptance:** iPhone Safari tap FS → chat, cameras, mic/cam controls, room code all
remain visible; no jump to bare native video player. Exit returns cleanly.
**Device-only verification:** must be checked on the real iPhone over Funnel.

### Phase C — RotateHint (retire the rotate transform on watch) + viewport/safe-area
**Scope:** Add a non-rotating `RotateHint` overlay shown when phone + portrait on the
watch screen (dismissible, `Z.rotateHint`). Ensure watch stage uses `100dvh`
semantics; add iOS bottom-toolbar cushion for the bottom bar; verify all chrome
clears `--sa-*`. Confirm `WatchView` is not wrapped in `LandscapePhone` (it isn't).
**Files:** `Party.jsx`, `styles.css`.
**Acceptance:** Portrait phone on watch shows the hint and a correctly-sized (not
occluded) UI; rotating to landscape hides the hint; bottom bar never sits under
Safari's toolbar or the home indicator.
**Device-only verification:** iOS toolbar overlap; safe-area on notched device.

### Phase D — Retire `LandscapePhone` rotate hack in the lobby
**Scope:** Replace the `transform: rotate(90deg)` `LandscapePhone` in the lobby with
the same `RotateHint`; let the library grid reflow for portrait. Remove
`usePortraitPhone`/`LandscapePhone` once unused; drop `Z.rotateHint` special-casing
if folded into RotateHint.
**Files:** `Party.jsx` (lobby branch), possibly `Library.jsx`.
**Acceptance:** Lobby on a portrait phone is usable without a rotated coordinate
space; safe areas and back-swipe behave normally.

### Phase E — Control-layer overflow menu + contrast
**Scope:** Split `MobileBottomBar` into primary (play, mic, cam, fullscreen) + a "⋯"
overflow popover (talk, hide-self, camera strip, settings) below a width threshold;
inline on wide phones. Bump idle button fill / add bar scrim for ≥3:1 contrast.
Derive camera-strip clearance from real bar height.
**Files:** `Player.jsx`, `Party.jsx` (MobileCameraStrip clearance).
**Acceptance:** On 740×360 nothing clips or horizontally scrolls; fullscreen always
reachable in one tap; icons meet contrast over a bright frame.

### Phase F — Gestures + reduced-motion
**Scope:** Double-tap left/right third to seek ∓10s (controllers) with ripple + label
and a movement threshold; single tap keeps toggling chrome. Add
`@media (prefers-reduced-motion: reduce)` to styles.css.
**Files:** `Party.jsx` (`onSurfaceTap` → richer handler), `styles.css`.
**Acceptance:** Double-tap seeks for controllers, toggles chrome for guests; no
gesture conflicts with iOS back-swipe; animations reduce under reduced-motion.
**Device-only verification:** touch double-tap timing on real phone.

---

## 5. Device test protocol (over the Funnel URL)

Test on the real iPhone (Safari) and, if available, an Android Chrome phone, at
`https://dsk-4161.tail0a3558.ts.net`. Join a party as a guest (and, on a second
device, as host) — the watch screen is behind Jellyfin login, so use a real login;
do not attempt to bypass it.

**Fullscreen / orientation**
1. Portrait → tap fullscreen. Android: expect true fullscreen + auto-landscape +
   all overlays. iPhone: expect faux-fullscreen (chrome-max, overlays kept) + rotate
   hint until you physically rotate.
2. Landscape → tap fullscreen: near full-bleed 16:9, controls fade after 3s, tap
   shows them.
3. Exit via the button, via Android back gesture, via iOS "done"/swipe. Confirm
   `immersive` state and the button icon reset every time; Android returns to
   portrait (orientation unlocked).
4. Rotate the device mid-playback: no crash, overlays reposition, hint appears/hides.

**Overlap / safe areas**
5. Notched iPhone: confirm the bottom bar clears the home indicator AND is not under
   Safari's bottom toolbar; top chips clear the notch/Dynamic Island in landscape
   (both left and right rotations).
6. Open chat sheet + camera strip + bar simultaneously in landscape: nothing
   overlaps the picture destructively; chat is dismissible; strip sits above the bar.
7. Movie visible (not letterboxed to a sliver) in immersive landscape.

**Controls / gestures**
8. All bar buttons are ≥44px and tappable one-handed; fullscreen reachable without
   horizontal scroll on the smaller phone.
9. Double-tap left/right seeks (controller) / toggles chrome (guest); single tap
   toggles chrome; no accidental back-swipe.
10. Icon contrast readable over a bright scene.

**Degradation**
11. Toggle iOS Reduce Motion: enter/exit and sheets crossfade instead of
    slide/scale; no jank.
12. Add to Home Screen (iOS) and reopen: faux-fullscreen is effectively full (no
    Safari chrome).

**What can only be verified on device (not in DevTools emulation):** real
`screen.orientation.lock` behaviour, iOS `webkitEnterFullscreen`/faux-FS chrome,
Safari dynamic-toolbar overlap, notch/home-indicator safe areas, and touch
double-tap timing. DevTools mobile emulation at 844×390 / 740×360 is useful for
layout/overflow/contrast only.

---

## Notes / assumptions
- Confirmed by code read: `LandscapePhone` wraps only the lobby, not `WatchView`; the
  watch screen currently has no forced-landscape and no rotate hint (F3/G7).
- `document.fullscreenEnabled` is the accepted signal that iPhone Safari lacks
  element FS while Android/iPad have it — this is the branch point the whole design
  hinges on.
- No live inspection of the watch screen was done (it is behind Jellyfin login with
  no credentials, per the brief); the plan is from code audit + platform behaviour +
  ui-ux-pro-max rules.
