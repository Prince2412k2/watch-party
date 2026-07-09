# Watchparty Redesign — Execution Plan (for Sonnet agents)

**Direction:** cinematic minimal, dark, monochrome. Content is the interface.
**Vibe reference:** Apple TV, Max, a premium OTT app — quiet chrome, artwork carries everything.

This document is the single source of truth. Every agent reads the whole
"Shared design system" + "Global rules" sections, then executes exactly one
**Agent Card**. Do not deviate from the tokens or rules. When a rule and your
taste disagree, the rule wins.

---

## 0. Hard constraints (non-negotiable — the user called these out)

1. **Monochrome. No color accent.** No orange/amber. No brand hue. The palette
   is neutral near-black → near-white. Color appears ONLY as semantic status
   (error red, a single muted "recording/live" red dot, muted-green success
   tick) and NEVER as decoration, brand, emphasis, active-state, or fill. If you
   are reaching for a colored highlight to make something "pop", stop — use
   weight, size, spacing, or brightness instead.
2. **No gradients.** None as fill, background, brand, placeholder, or button.
   The ONLY permitted `linear-gradient` in the entire app is a neutral
   **black-alpha legibility scrim** over real photographic artwork (hero/backdrop
   behind text), e.g. `linear-gradient(0deg, rgba(0,0,0,.85), transparent)`.
   It must be single-hue black-alpha, never colored, never multi-stop-decorative.
   Fake "gradient poster" placeholders are banned — use a solid `--surface` tile
   with a centered monospace title when artwork is missing.
3. **No liquid glass.** No `backdrop-filter`, no frost, no refraction, no
   specular sheen, no `glass()` visual. Surfaces are flat, solid, opaque.
   (`glass.jsx` already returns flat solids — keep it that way; do not reintroduce
   blur. A modal *scrim* may use a light `backdrop-filter: blur(2px)` on the
   page behind a dialog — that is the one allowed blur, and only on scrims.)
4. **Active-nav treatment is minimal.** The old boxed pill (filled background +
   inset colored rail + colored dot) is rejected. Active = brighter + heavier
   text/icon only. No background fill, no rail, no dot, no color. See §Nav.
5. **Video player is minimal.** See the Player Agent Card. Auto-hiding controls,
   one thin control row, essential controls only, no boxed skin, no clutter.

---

## 1. Shared design system (COPY THESE VALUES EXACTLY)

These land in Phase 0 and every screen consumes them. Values are given so an
agent reading only its own card still uses the right numbers.

### 1.1 Color tokens

Monochrome neutral ramp (cool-neutral near-black, not warm, not pure #000):

| Token        | Value                     | Use |
|--------------|---------------------------|-----|
| `bg`         | `#0a0a0b`                 | page ground, behind everything |
| `surface`    | `#141416`                 | cards, panels, inputs |
| `surface2`   | `#1e1e21`                 | raised / hover surface |
| `surface3`   | `#2a2a2e`                 | pressed / selected surface |
| `text`       | `#f4f4f5`                 | primary text |
| `dim`        | `rgba(244,244,245,.62)`   | secondary text |
| `faint`      | `rgba(244,244,245,.36)`   | tertiary text / meta |
| `line`       | `rgba(255,255,255,.08)`   | hairline dividers/borders |
| `line2`      | `rgba(255,255,255,.14)`   | stronger border / input outline |
| `primary`    | `#f4f4f5`                 | primary CTA fill (near-white "Play" pill) |
| `onPrimary`  | `#0a0a0b`                 | text/icon on the near-white primary |
| `scrim`      | `rgba(0,0,0,.6)`          | flat darkening over artwork |

Semantic status (functional only — never decorative, never brand):

| Token     | Value       | Use (and ONLY this use) |
|-----------|-------------|--------------------------|
| `danger`  | `#e0655e`   | destructive actions, errors |
| `live`    | `#e0655e`   | "recording/live/downloading now" dot (same red, meaning "active transfer/recording") |
| `success` | `#5ab98a`   | a completed/verified tick, sparingly |

Progress bars, buffered ranges, focus rings, hovers, and every non-status
highlight are **neutral** (white / white-alpha), NOT colored.

- Progress fill: `text` (near-white) on a `rgba(255,255,255,.15)` track.
- Focus ring (keyboard): `2px solid var(--text)`, `outline-offset: 2px`.
  (Neutral, not colored — accessibility ring is white.)

### 1.2 Typography

One family. No serif. No second display face.

- **Body/UI:** `'Hanken Grotesk', system-ui, -apple-system, sans-serif` (already
  loaded in `styles.css`).
- **Data/meta/timestamps:** `'JetBrains Mono', ui-monospace, monospace` — used
  for years, runtimes, counts, codes, download stats. Enable
  `font-variant-numeric: tabular-nums` wherever digits align.

Type scale (px, root 16) — stay on it:

| Role      | Size | Weight | Tracking | Notes |
|-----------|------|--------|----------|-------|
| hero      | 44–52| 800    | -0.03em  | detail/hero titles only, `text-wrap: balance` |
| display   | 30   | 800    | -0.03em  | page/grid titles |
| title     | 22   | 700    | -0.02em  | rail/section headers |
| section   | 20   | 700    | -0.02em  | sub-sections |
| body      | 15   | 500    | normal   | overview text, line-height 1.6, max ~65ch |
| label     | 13.5 | 600    | normal   | buttons, nav rows |
| meta      | 11.5 | 700    | .14em    | mono, uppercase eyebrows/counts |

### 1.3 Spacing, radius, motion

- **Spacing scale (px):** 4, 8, 12, 16, 20, 28, 40, 64. Use generously — this
  design is defined by whitespace. Desktop content gutters: 44px. Rail vertical
  gap between sections: 44px. Mobile gutters: 16px.
- **Radius:** controls/inputs 10px; cards/posters 12px; large panels 16px;
  pills 999px; full-bleed regions 0.
- **Elevation:** flat at rest (no shadow). Hover-lift on cards:
  `transform: translateY(-4px)` + `box-shadow: 0 16px 44px rgba(0,0,0,.62)`.
  Overlays/modals: `box-shadow: 0 24px 60px rgba(0,0,0,.7)`. No inset sheens.
- **Motion:** 150–260ms, `cubic-bezier(.2,.8,.2,1)` (ease-out). Only
  transform/opacity. Respect `prefers-reduced-motion` (already handled globally
  in `styles.css`). No decorative/looping animation except the essential
  "live" pulse dot and loading skeletons.
- **Borders:** hairline `1px solid var(--line)` for separation only where two
  same-tone surfaces meet. Prefer spacing over borders. No border on posters.

### 1.4 Surfaces & chrome philosophy

- Sidebars/bars are **flush** (edge-to-edge, `border-right`/`border-bottom`
  hairline), never floating rounded panels with big shadows.
- Content panes are **flush to the viewport edge** (full-bleed), not inset
  rounded cards.
- Chrome fades away: top bars sit over content with a black-alpha scrim (the
  one allowed gradient) and low visual weight; the artwork/content dominates.

---

## 2. Global rules (apply on every screen)

- **Nav rows (§Nav — the corrected spec):**
  - Inactive: `color: dim`, weight 500, icon stroke 1.7.
  - Hover: `color: text`, background `rgba(255,255,255,.04)`, radius 10.
  - **Active: `color: text`, weight 700, icon stroke 2.0, icon color `text`.
    NO background fill, NO left rail/bar, NO dot, NO color.** The only signal is
    brighter + heavier. (Optional, subtle: active row may keep the same faint
    hover background `rgba(255,255,255,.04)` so it reads as "here" — but nothing
    colored and no rail.)
  - Wordmark: plain `Watchparty` in `text`, weight 700, `-0.01em`. No dot, no
    logo mark, no gradient, no color.
- **Buttons:**
  - Primary (one per view max): near-white `primary` fill, `onPrimary` text,
    pill radius, weight 700. Hover `transform: scale(1.02)`.
  - Secondary/icon: `surface` fill, `1px solid line`, `dim` text → `text` on
    hover, `surface2` bg on hover. Radius 10.
  - Tertiary: text-only, `dim` → `text`.
- **Cards/posters:** solid `surface` behind the image (for load state), radius
  12, no border, flat at rest, hover-lift per §1.3. Missing-art fallback = solid
  `surface` tile + centered mono title, never a gradient.
- **Empty / error / loading states are required** on every data surface:
  - Loading = skeleton blocks (`surface` with a subtle shimmer already defined
    as `@keyframes shim`; keep it neutral).
  - Empty = one line of `dim` copy + (if relevant) a single primary action.
  - Error = inline `danger`-tinted row (`rgba(224,101,94,.12)` bg,
    `1px solid rgba(224,101,94,.35)`, `danger` text). Never `alert()`.
- **Accessibility:** visible white focus ring (§1.1); `alt` on meaningful
  images; icon-only buttons need `title`/`aria-label`; keep hit targets ≥40px
  (≥44px on mobile); maintain ≥4.5:1 text contrast (the ramp above satisfies
  this on `bg`).
- **Copy:** sentence case, active voice, specific. No exclamation marks, no
  "Oops". Buttons say the action ("Start a watch party", "Remove", "Join").
- **Do not touch behavior.** This is a visual redesign. Do not change data
  fetching, socket/sync logic, party/auth flows, routing, or component props/
  public signatures. Only markup/styles/layout inside each owned file.

---

## 3. Video player — minimal spec (read by the Player agent)

Goal: the movie is the UI. Chrome appears only on intent, then leaves.

- **Stage:** full-bleed black. Video fills; `object-fit: contain`.
- **Auto-hide:** all controls hidden after **2.5s** of no pointer movement (and
  while playing). Reveal on `mousemove`/tap/focus. When hidden, cursor hides too
  (`cursor: none` on the stage). Never auto-hide while paused or while a menu is
  open.
- **One control row**, pinned bottom, over a **black-alpha bottom scrim** (the
  single allowed gradient — `linear-gradient(0deg, rgba(0,0,0,.8), transparent)`,
  ~120px tall). Row contents, left→right, single line:
  1. Play/Pause (only large-ish icon).
  2. Current time (mono, tabular).
  3. **Scrubber** (flex-grow): thin (4px, grows to 6px on hover). Played =
     `text` (near-white). Buffered = `rgba(255,255,255,.28)`. Track =
     `rgba(255,255,255,.14)`. Round thumb (10px) visible only on hover/scrub.
  4. Duration (mono, tabular, `dim`).
  5. Volume (icon; slider reveals on hover — desktop only).
  6. Settings/quality (icon → small flat menu, `surface`, no glass).
  7. Fullscreen (icon).
  All icons monochrome, stroke ~1.9, `dim` → `text` on hover, no boxes/borders
  around them.
- **Center:** nothing on desktop. On tap (mobile) a single large play/pause
  ghost that fades. Double-tap left/right = ∓10s with a brief neutral ripple
  (keep existing seek logic).
- **Top of stage (minimal):** only when controls are visible — left: title +
  back; right: party-essential toggles (participants, chat, camera, settings)
  as small monochrome icons, no labels, no boxes. Keep the room/sync features
  but render them quiet.
- **Guest (no control):** identical thin scrubber but **read-only** (no thumb,
  no pointer events); still shows position/buffer. A tiny `dim` "Host controls
  playback" hint, text-only, no lock-box.
- **Buffering / catch-up:** a centered thin neutral spinner (2px ring, `text`
  top, transparent rest) + one line of `dim` text ("Catching up…"). No colored
  spinner, no gradient.
- **Loudness/quality/sync menus:** flat `surface` popovers, hairline border,
  radius 12, no blur, no gradient.
- **Preserve all existing sync/transport wiring** (`useSyncPlay`, transport
  intent, buffer-aware seek, `applyingRef`, quality/ABR). Only restyle and
  restructure the control DOM; keep the event/authoring paths intact.

---

## 4. Parallelization model (git worktrees, multi-agent)

**Conflict rule:** two agents may never edit the same file. Ownership below is
disjoint. Shared/foundation files are edited ONLY in Phase 0.

**Branch/worktree convention** (base branch = `redesign-v2`, cut fresh from
`main`; do NOT build on the old `redesign` branch — it carries the rejected
amber/nav choices):

```
# once, by the orchestrator:
git branch redesign-v2 main

# each agent, in its own worktree:
git worktree add ../wt-<agent-id> -b redesign/<agent-id> redesign-v2
# ...work only inside owned files...
git -C ../wt-<agent-id> add <owned files> && git -C ../wt-<agent-id> commit -m "..."
```

**Phase order (dependencies):**

- **Phase 0 — Foundation (1 agent, BLOCKING).** Must complete and be merged into
  `redesign-v2` before any Phase 1 agent starts (they branch from the merged
  result so they inherit the final tokens/chrome).
- **Phase 1 — Screens (9 agents, PARALLEL).** Each branches from `redesign-v2`
  (post-Phase-0), owns disjoint files, commits to its own branch.
- **Phase 2 — Integration (1 agent, BLOCKING).** Merges all Phase 1 branches
  into `redesign-v2`, resolves the (rare) shared drift, runs the full build +
  visual QA, fixes cross-screen inconsistencies, opens the PR to `main`.

Because Phase 1 file sets are disjoint, merges are expected to be clean.

---

## 5. Agent Cards

> Every card: work ONLY in "Files owned". Read §1–§3. After changes run
> `cd app/client && npx vite build` and confirm it builds. Do not edit
> `package.json` (no new dependencies). Do not change component prop signatures
> or exported names that other files import. Commit on your own branch.

### Phase 0 — `foundation` (BLOCKING, do first)

**Goal:** the corrected monochrome, gradient-free, glass-free token layer +
shared chrome that every screen inherits.

**Files owned:**
- `app/client/src/styles.css`
- `app/client/src/glass.jsx`
- `app/client/src/lib/ui.jsx`
- `app/client/src/mobile/theme.js`
- `app/client/src/App.jsx`
- `app/client/index.html` (title + `theme-color` → `#0a0a0b`)

**Do:**
1. `styles.css`: set `:root` to the §1.1 tokens (add `--surface3`, `--live`,
   `--danger`, `--success`, `--scrim`; remove any leftover `--live` amber /
   `--accent` color / serif / grain / `--blur` usage). Font import = Hanken
   Grotesk + JetBrains Mono only. Focus ring = white (§1.1). `.glass`/`.icon-btn`
   flat. Remove `.grain`. Keep the animation keyframes + reduced-motion block.
2. `glass.jsx`: keep `glass()` returning flat solids (no blur/refraction);
   `GlassDefs` stays a no-op. Confirm no `backdrop-filter` anywhere.
3. `lib/ui.jsx`: `C` = §1.1 tokens (keys: bg, surface, surface2, surface3, text,
   dim, faint, line, line2, accent[=primary near-white], accentDim, accentSoft
   [neutral white-alpha], onAccent, live, danger→`red`, green→success, glass
   [=surface], glassHi[=surface2]). Rebuild shared chrome: `GlassBtn` (flat
   secondary/pill), `NavRow` (**corrected active spec §Nav — no box/rail/dot/
   color**), `Sidebar` (flush, plain wordmark), `TopBar` (flush, black-alpha
   scrim), `Notice`, `Spinner` (neutral). Keep the `Ic` icon set and all export
   names/signatures unchanged.
4. `mobile/theme.js`: `T` = §1.1 tokens; `brand`→ keep as `success` green ONLY
   for functional progress on mobile OR switch mobile progress to white to match
   desktop (preferred: white progress, `success` only for ticks). `primary` =
   near-white, `onLight` = `#0a0a0b`. **Delete `BRAND_GRADIENT`** and replace its
   usages contract: export `AVATAR_BG = '#1e1e21'` (solid) instead; `AMBIENT` →
   `'none'` (no ambient glow). `TYPE.display/title` = Hanken Grotesk (no serif).
   NOTE: since screens import `BRAND_GRADIENT`/`AMBIENT`, keep the export NAMES
   but make them solid/none so mobile screen agents don't break; they will
   remove usages in their own files.
5. `App.jsx`: remove any `GlassDefs`/grain mounts already gone; ensure nothing
   references removed symbols.

**Acceptance:** `npx vite build` passes. Grep shows zero `linear-gradient` with
a non-black color, zero `backdrop-filter` outside a modal scrim, zero hex that
is orange/amber, no serif font. Nav active state has no background rail/dot.

---

### Phase 1 (parallel — each branches from merged `redesign-v2`)

#### A1 — `library` (desktop Library)
**Files owned:** `app/client/src/pages/Library.jsx`
**Depends on:** foundation.
**Do:** Full cinematic-minimal pass. Full-bleed backdrop hero for the top
item (real Jellyfin artwork, black-alpha scrim only), near-white Play pill,
flat circular secondary actions (no glass). Flush sidebar (its internal
`Sidebar`) + flush content pane (already flush — keep). Art-forward rails,
generous 44px gutters/gaps, flat-at-rest / hover-lift posters. Remove the green
"NEW" pill → neutral (`dim` text on `rgba(0,0,0,.6)` chip) — no color. Resume
progress bar = white, not colored. Grid/Details/Cast all flat, no glass, no
gradient. Keep all data hooks, mirror logic, and `open/pick/openView` wiring.
**Acceptance:** builds; no color accents; no gradient except hero legibility
scrim; posters use real art with `surface` fallback.

#### A2 — `browse` (desktop Find/Download)
**Files owned:** `app/client/src/pages/FindDownload.jsx`
**Depends on:** foundation.
**Do:** Restyle search/browse + the movie/series detail + release picker to the
system. Keep the "Remove from library" flow and all request/grab/poll logic.
Detail view = same hero language as Library (backdrop + scrim + near-white
primary). Status chips (searching/monitoring/downloading) = neutral surfaces +
mono meta text; the only color allowed is `live` (red) for an active-download
dot and `danger` for failures — no green/amber emphasis. Seed-count coloring →
neutral (drop green/amber; use `dim`/`text`, `danger` only for 0-seed/failed).
**Acceptance:** builds; picker + detail + grids consistent with Library.

#### A3 — `downloads` (desktop Downloads + detail)
**Files owned:** `app/client/src/pages/Downloads.jsx`,
`app/client/src/components/DownloadDetail.jsx`
**Depends on:** foundation.
**Do:** Restyle the active/failed download list, progress rings/bars, the
detail overlay, and the delete/confirm dialog. Progress = white on
white-alpha track (no colored bar/ring). "Active" state may use the `live` red
dot only. Failed = `danger`. Sparkline (if any) = neutral `text` line, faint
grid, no gradient fill. Delete confirm = flat `surface` dialog, scrim behind.
**Acceptance:** builds; rings/bars neutral; dialog flat.

#### A4 — `login` (desktop Login)
**Files owned:** `app/client/src/pages/Login.jsx`
**Depends on:** foundation.
**Do:** Minimal centered auth. No gradient orb, no glass card. Solid `surface`
form on `bg`, hairline inputs, near-white primary submit, inline `danger` error
row (no `alert`). Wordmark plain. Generous whitespace; single column; ≤ ~380px
form. Keep the auth submit logic and field names.
**Acceptance:** builds; zero gradient/glass; error inline.

#### A5 — `room-shell` (Lobby + waiting + party frame)
**Files owned:** `app/client/src/pages/Lobby.jsx`,
`app/client/src/components/WaitingRoom.jsx`, `app/client/src/pages/Party.jsx`
**Depends on:** foundation.
**Do:** Restyle the lobby (shared-browsing frame), the waiting-approval screen,
and the Party page's non-player chrome (layout scaffold, banners, host/guest
framing). Do NOT restyle the video controls (that's A6) or the in-room
overlays owned by A7 — only the surrounding frame/layout/empty-waiting states.
Keep all socket/party state wiring and props passed to child components.
**Acceptance:** builds; frame flat/monochrome; no behavior change.

#### A6 — `player` (minimal video player) — largest, most important
**Files owned:** `app/client/src/components/Player.jsx`
**Depends on:** foundation.
**Do:** Implement the **§3 minimal player** exactly. Rebuild the control DOM:
auto-hide, single thin control row over a black-alpha scrim, monochrome icons,
white scrubber (played) / white-alpha (buffered/track), read-only guest
scrubber, neutral buffering spinner, flat quality/volume popovers. Remove the
vidstack skin box look; keep the media element + `useSyncPlay` + transport
intent + buffer-aware seek + ABR wiring **unchanged** (only restyle/restructure
the surrounding controls and overlays). Keep `Player`'s exported prop signature
so `Party.jsx`/mobile `Watch.jsx` keep working.
**Acceptance:** builds; controls auto-hide after 2.5s; one control row; no
colored highlights (scrubber/progress white); no boxed skin; sync still authored
through the same paths (verify transport handlers untouched).

#### A7 — `in-room` (chat, cameras, room controls)
**Files owned:** `app/client/src/components/RoomControls.jsx`,
`app/client/src/components/Chat.jsx`, `app/client/src/components/CameraGrid.jsx`,
`app/client/src/components/CameraTile.jsx`, `app/client/src/components/Dock.jsx`
**Depends on:** foundation.
**Do:** Restyle in-room overlays to quiet monochrome: chat panel/sheet (flat
`surface`, hairline, no glass), camera tiles (flat, rounded 12, `live` red dot
only for active speaker/recording — a small ring, not a colored border-heavy
box), room controls menu (flat popover), dock. Speaking indicator = neutral or
`live` red dot, never green bars unless kept as neutral white bars. Keep all
LiveKit/socket/collab wiring and props.
**Acceptance:** builds; overlays flat/monochrome; no glass/gradient.

#### A8 — `mobile-shell` (mobile primitives + shell)
**Files owned:** `app/client/src/mobile/MobileApp.jsx`,
`app/client/src/mobile/TabBar.jsx`, `app/client/src/mobile/JoinSheet.jsx`,
`app/client/src/mobile/ui/TopBar.jsx`, `app/client/src/mobile/ui/Sheet.jsx`,
`app/client/src/mobile/ui/Rail.jsx`, `app/client/src/mobile/ui/Poster.jsx`,
`app/client/src/mobile/ui/Skeleton.jsx`, `app/client/src/mobile/ui/Icon.jsx`
**Depends on:** foundation.
**Constraint:** do NOT change the exported prop signatures of `ui/*` components
(A9 consumes them). Restyle internals only.
**Do:** Tab bar (flush bottom, hairline top, active = brighter icon+label, no
colored pill/rail/dot), top bar (flush), sheets (flat `surface`, scrim may blur
2px), rails/posters/skeletons neutral. Remove ambient glow / brand gradient
usages here.
**Acceptance:** builds; tab active state monochrome; primitives keep prop APIs.

#### A9 — `mobile-screens`
**Files owned:** `app/client/src/mobile/screens/Login.jsx`,
`app/client/src/mobile/screens/Home.jsx`,
`app/client/src/mobile/screens/Browse.jsx`,
`app/client/src/mobile/screens/Downloads.jsx`,
`app/client/src/mobile/screens/Watch.jsx`
**Depends on:** foundation (and A8's frozen `ui/*` prop APIs — styling only, so
safe to run in parallel with A8).
**Do:** Restyle all five mobile screens to the system: remove every
`BRAND_GRADIENT`/`AMBIENT` usage (replace with solid `surface`/`AVATAR_BG` or
nothing), progress = white, status dots = `live` red only, monochrome
everywhere, generous spacing, art-forward. `Watch.jsx` just wraps `Player`
(owned by A6) — keep the wrapper thin and don't restyle the player controls
here. Keep all data/party wiring and screen props.
**Acceptance:** builds; zero gradient/glass; matches desktop language.

---

### Phase 2 — `integration` (BLOCKING, last)

**Do:**
1. Merge `redesign/foundation` (already in `redesign-v2`), then A1–A9 branches
   into `redesign-v2` in any order; resolve conflicts (expected only if an agent
   strayed outside owned files — if so, prefer the owner's version).
2. `cd app/client && npx vite build` — must pass.
3. Global grep gate (must all return nothing meaningful):
   - colored gradients: `grep -rn "linear-gradient" src | grep -vi "rgba(0,0,0"`
     (only black-alpha scrims allowed).
   - blur: `grep -rn "backdrop-filter" src` (only modal scrims).
   - banned hues: `grep -rniE "#e0a4|#3ecf|#6a8bff|#d16aff|orange|amber" src`.
4. Visual QA pass: launch the app (see repo run instructions), walk every
   screen at desktop + mobile widths, confirm: monochrome, no gradient, flat
   surfaces, clean nav active state, minimal auto-hiding player. Fix cross-screen
   inconsistencies (spacing, type scale drift) directly.
5. Run the sync harness + unit tests to prove player restyle didn't break
   transport: `cd app && node --test` and the harness suite. All green.
6. Open PR `redesign-v2 → main` with a screenshot-based summary.

---

## 6. Definition of done (whole redesign)

- Every screen is dark, monochrome, flat, gradient-free, glass-free.
- Nav/tab active states carry no color/box/rail/dot — brightness+weight only.
- Video player is minimal with auto-hiding single-row controls.
- No behavior/logic/prop-signature changes; sync harness + unit tests pass.
- `npx vite build` passes; grep gates clean.
- One PR to `main`.
