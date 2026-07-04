# Watchparty — Mobile Design & Architecture Spec

Scope: a **new phone presentation layer** over the existing data/logic engine. On phones we render a native-feeling app; on desktop/tablet the existing UI is untouched. Same URLs/routes, same contexts/hooks/API, same sync + LiveKit engine. This document is the contract every builder agent follows.

Grounded in a read of: `App.jsx`, `router.js`, `context/{AuthContext,PartyContext}.jsx`, `hooks/*`, `pages/{Login,Library,FindDownload,Downloads,Party,Lobby}.jsx`, `components/{Player,CameraGrid,Chat,Dock,RoomControls,CameraTile}.jsx`, `styles.css`, `glass.jsx`, `watchLayers.js`, `sync/*`, `vite.config.js`, `server/index.js`.

---

## 0. Non-negotiables (inherited from the brief)

- **Device-detected.** Phones → new mobile tree. Desktop/tablet → existing app, byte-for-byte unchanged. Never regress desktop.
- **Same routes.** `/login`, `/library`, `/discover`, `/downloads`, `/party/:code`, `/party/new?itemId=`. Shared links + QR join must still resolve.
- **Reuse the engine.** All contexts, hooks, socket, and REST endpoints are consumed verbatim. The watch screen (Player + `useSyncPlay` + `useLiveKit`) is **wrapped, not rebuilt** (see §2.4).
- **Safari/Chrome tuned.** `100dvh`, `env(safe-area-inset-*)`, ≥16px inputs, ≥44px targets, momentum scroll, no hover-only affordances, no URL-bar layout jump (§5).
- **PWA / hidden chrome.** Manifest + iOS/Android meta + icons so "Add to Home Screen" launches full-screen (§4).
- **Live app.** No container restart, no destructive git/docker, no `.env.local` edits.

---

## 1. Visual Direction — "Midnight Glass"

A committed, opinionated extension of the aesthetic already living in the codebase (Sen-Player-inspired: dark, atmospheric, poster-forward, liquid glass). The mobile tree does **not** invent a competing look — it re-cuts the existing one into an app-like phone shell so desktop and phone read as one product.

### 1.1 Feel
Cinematic, calm, poster-first. The artwork carries the color; chrome is near-black glass that floats over content. Motion is short and springy (iOS-native cadence). It should feel like a first-party streaming app, not a website in a phone.

### 1.2 Type system
Fonts are already loaded in `styles.css` via Google Fonts (`Hanken Grotesk`, `JetBrains Mono`, `Geist`). **Keep this** — it is the product's voice. Do not add new families.

- **Display / UI — Hanken Grotesk** (weights 400/500/600/700/800). Tight tracking on large headings (`letter-spacing: -0.02em`). This is the distinctive, non-generic sans that separates us from default system-UI slop.
- **Metadata / codes / numbers — JetBrains Mono** (400/500/600). Used for: party codes, runtimes, years, download %/speed, S·E labels, timeline timestamps. The mono/grotesk contrast is the signature.
- **Fallbacks:** `'Hanken Grotesk', system-ui, -apple-system, sans-serif` and `'JetBrains Mono', ui-monospace, monospace` (already the pattern in the pages).

Mobile type scale (rem, root 16px):

| Token | size / line / weight | use |
|---|---|---|
| `display` | 30 / 1.05 / 800 | screen hero title, Login H1 |
| `title` | 21 / 1.15 / 800 | rail headers, sheet titles |
| `headline`| 17 / 1.25 / 700 | card titles, list rows |
| `body` | 15 / 1.5 / 500 | descriptions, chat |
| `label` | 13 / 1.3 / 600 | buttons, tab labels |
| `meta` | 11.5 mono / 1.2 / 700 | codes, %, S·E, kbd caps (uppercase, `.14em`) |
| `input` | **16** / 1.4 / 500 | **all text inputs — never below 16px (iOS zoom)** |

### 1.3 Color / theme (dark-first, canonical)
The product is **intentionally dark-first** — it is a shared cinema. Dark is the canonical theme and the one the manifest/`theme-color` commits to. There is no light "app chrome"; a future light mode would only re-skin surfaces, and the token layer below is where it would hook in. Reconcile the two divergent palettes in the code (`styles.css :root` vs. the per-page `C = {…}` objects) into **one shared mobile token module** so every mobile screen is identical.

Create `app/client/src/mobile/theme.js`:

```js
export const T = {
  bg:        '#0b0d10',   // page ground (matches Library/FindDownload/Downloads)
  bgDeep:    '#08080a',   // status-bar / manifest theme-color, behind everything
  surface:   '#16191e',
  surface2:  '#20242b',
  text:      '#F1F3F6',
  dim:       '#A6ADB8',
  faint:     '#6B7280',
  line:      'rgba(255,255,255,.08)',
  line2:     'rgba(255,255,255,.16)',
  brand:     '#3ecf7e',   // green — live/active/accent (downloads, presence, progress)
  brandInk:  '#06210f',   // ink on brand
  onLight:   '#0a0b0d',   // ink on the white primary button
  primary:   '#FFFFFF',   // "Play"/primary pill (Sen-Player white)
  red:       '#FF6B6B',
  glass:     'rgba(20,24,30,.62)',
  glassHi:   'rgba(38,44,54,.7)',
}
export const SANS = "'Hanken Grotesk', system-ui, -apple-system, sans-serif"
export const MONO = "'JetBrains Mono', ui-monospace, monospace"
export const R = { sm: 12, md: 16, lg: 22, pill: 999 }
export const EASE = 'cubic-bezier(.2,.8,.2,1)'   // spring-ish, iOS cadence
```

Ambient backdrop (reuse on every shell screen, already the Library pattern): dual radial glows in brand-green + periwinkle over `T.bg`. Accent gradient for logo/brand marks: `linear-gradient(135deg, #3ecf7e, #6a8bff, #d16aff)`.

**Glass:** reuse `glass('clear'|'light'|'medium'|'heavy', {refract})` from `glass.jsx` and mount `<GlassDefs/>` (already mounted at app root). The bottom tab bar and top bars are glass `medium`. Do not hand-roll new blur recipes.

### 1.4 Motion language
- **Entrances:** reuse existing keyframes in `styles.css` — `up` (list/section rise), `in` (pop), `sheetIn` (right/bottom sheet), `scrimIn` (scrim fade). Add one mobile keyframe `tabIn` for screen cross-fades if needed.
- **Timing:** `.22s–.28s` with `EASE`. Tap feedback: `transform: scale(.97)` on `:active` (touch has no hover — use active state, not hover).
- **Shared element:** poster → detail uses a brief scale/opacity rise (`up`), not a full FLIP (keep it cheap and reliable on mobile GPUs).
- **Respect `prefers-reduced-motion`** — the global reduce block in `styles.css` already collapses these; do not bypass it.

### 1.5 App-shell pattern
Fixed full-bleed column sized to the **dynamic** viewport, never the layout viewport:

```
┌──────────────────────────────┐  position: fixed; inset: 0;
│  Top bar (per screen)         │  height: 100dvh; padding-top: var(--sa-t)
│  — glass, sticky              │
├──────────────────────────────┤
│                               │
│  Scroll region                │  the ONLY scroller; momentum; overscroll
│  (momentum, safe-area padded) │  padding-bottom: tab-bar height + --sa-b
│                               │
├──────────────────────────────┤
│  Floating glass Tab Bar       │  fixed bottom; padding-bottom: var(--sa-b)
└──────────────────────────────┘  (absent on the immersive Watch screen)
```

- The shell itself never scrolls; a single inner region scrolls with momentum. This is what defeats URL-bar layout jump (§5).
- Tab bar is a floating glass pill row, not full-width edge-to-edge, so it reads as an app control. It shows on Home / Browse / Downloads. It is **hidden** on Login and on the immersive Watch screen.

---

## 2. Architecture

### 2.1 Directory
All new code lives under **`app/client/src/mobile/`**. Nothing outside this dir changes except: (a) a small device-branch in `App.jsx`, (b) `index.html` meta, (c) new `app/client/public/` assets, (d) a few additive lines in `styles.css` (§5). Desktop pages/components are not edited.

```
app/client/src/mobile/
  MobileApp.jsx        # shell: route switch for phone shell screens + tab bar
  theme.js             # tokens (§1.3)
  ui/
    Icon.jsx           # lift the shared stroke-icon set + <Icon> (dedupe from pages)
    Poster.jsx         # 2:3 poster w/ failed-art guard (port Library's <Img>)
    Rail.jsx           # swipeable horizontal rail (NO hover arrows — §5)
    Sheet.jsx          # bottom sheet (scrim + sheetIn) — join, filters, season picker
    TopBar.jsx         # per-screen glass header (title, back, actions)
    Skeleton.jsx       # shimmer placeholders (reuse `shim` keyframe)
  TabBar.jsx           # bottom nav (Home / Browse / Downloads + center Party action)
  screens/
    Login.jsx
    Home.jsx
    Browse.jsx
    Downloads.jsx
    # Watch: NOT a new screen — delegates to existing pages/Party.jsx (§2.4)
  JoinSheet.jsx        # join-by-code + QR entry point
```

### 2.2 Device detection & routing

`usePhone()` (already in `hooks/useIsMobile.js`) is the detector: `(pointer: coarse) and (max-width: 900px), (pointer: coarse) and (max-height: 500px)`. It is coarse-pointer gated, so a narrow desktop window keeps desktop chrome — correct. Use `usePhone()` (not `useIsMobile()`) for the tree switch so a rotated phone in landscape still gets the mobile tree.

Edit `App.jsx`'s `Router()` with a **minimal, surgical branch**. Two hard rules:

1. **Party routes are device-agnostic and must be rendered by a single shared code path**, above the phone branch, so a rotation that flips `usePhone()` never remounts a live watch session (that would tear down LiveKit + `useSyncPlay`). `Party.jsx` already self-adapts to phones internally via `usePhone()`.
2. All auth redirect effects (`returnTo`, login bounce) stay exactly as they are.

```jsx
function Router() {
  const { user, loading } = useAuth()
  const path = useRoute()
  const phone = usePhone()
  // …existing redirect effects unchanged…
  if (loading) return null
  if (!user && path !== '/login') return null
  if (path === '/') return null

  // (1) Party routes — identical element in both device modes (mount-stable).
  if (path.startsWith('/party/')) return <PartyRoute user={user} path={path} />

  // (2) Phone shell screens — new mobile tree.
  if (phone) return <MobileApp path={path} />

  // (3) Desktop — existing switch, verbatim.
  if (path === '/login')     return <Login onSuccess={…} />
  if (path === '/library')   return <Library />
  if (path === '/discover')  return <FindDownload />
  if (path === '/downloads') return <Downloads />
  return <div>404</div>
}
```

`PartyRoute` is a tiny extraction of the current `/party/*` block (the `PartyProvider` + `<Party>` wiring) so both device modes share the exact same element. `MobileApp` owns navigation between shell screens by reading `path` and calling the existing `navigate()` from `router.js` — **no new router library**; the custom `pushState` + `useRoute` mechanism is reused so shared links and QR joins keep working.

Note on `/login`: phones render `mobile/screens/Login.jsx`; that's inside `MobileApp` (path `/login` while `!user`). Desktop keeps `pages/Login.jsx`.

### 2.3 What each screen reuses (engine map)

| Screen | Context / hooks | REST endpoints |
|---|---|---|
| **Login** | `useAuth().login`, `navigate` | `/api/auth/login`, `/api/auth/me` |
| **Home** | `useAuth()`, port Library's `useDownloads` + `useFailingCount`, `isActiveState` | `/api/library/home`, `/api/library/latest`, `/api/library/items/:id/children`, `/api/library/image/:id?type=`, `/api/servarr/downloads/enriched` |
| **Browse** | `useAuth()`, `useTorrents`, `useFailingCount`, `navigate` | `/api/servarr/search`, `/releases`, `/request`, `/request-season`, `/downloads/enriched` |
| **Downloads** | `useTorrents`, `useFailingCount` | `/api/servarr/downloads/enriched`, qbittorrent pause/resume/delete endpoints already used by desktop `Downloads.jsx` |
| **Watch/Party** | `useParty()`, `useSocket`, `useLiveKit`, `useSyncPlay` (via Player), `useServerClock`, `usePushToTalk`, `useHideSelf`, `usePhone` | `/api/livekit/token`, `/api/library/hls-url?itemId=&abr=1`, socket `party:*` / `sync:*` / `chat:*` / `browse:*` / `camera:*` |

Contract facts to build against (verified in source):
- `useAuth()` → `{ user, loading, login(u,p), logout }`; `user = { userId, name, … }`.
- `useParty()` → `{ session, role, layoutMode, chatOpen, chatRipple, alertMode, toasts, createParty, createRoom, joinParty, navigateBrowse, sendPointer, selectMedia, backToLobby, approveUser, rejectUser, kickUser, transferHost, endParty, setCollaborative, setSyncMode, sendMessage, removeCamera, setLayout, toggleChat, openChat, closeChat, setAlertMode }`. Provider needs `userId`.
- `useSocket()` → singleton `{ socket, connected }`.
- Party code shape: 8-char hex `^[0-9A-F]{8}$` (server `randomUUID().slice(0,8).toUpperCase()`). Join sheet must validate this.
- Poster URL helper: `` `/api/library/image/${id}?type=Primary|Thumb|Backdrop` ``. Port Library's `failedArt` Set guard so a 404 is never re-requested.
- Downloads polling: `/api/servarr/downloads/enriched` returns items with `displayTitle / subtitle / posterUrl / kind / progress / state / dlspeed / numSeeds / numLeechs / hash`; degrades to `[]` when Servarr is unconfigured. Active filter = `isActiveState(t.state)` from `useTorrents.js`.

### 2.4 Watch screen — **wrap, do not rebuild** (decision + justification)

**Decision: reuse `pages/Party.jsx` as the mobile Watch screen with zero forking of the engine.** The mobile Watch "screen" is literally `<PartyProvider><Party/></PartyProvider>` — the same element the desktop path renders.

Why wrap and not rebuild:
- `Party.jsx` / `Player.jsx` **already contain a complete, tuned phone watch UI** gated on `usePhone()`: immersive `100dvh` stage, `MobileBottomBar`, `MobileCameraStrip`, dismissible `ChatSheet` + scrim, iOS CSS faux-fullscreen vs. element-fullscreen branching, orientation lock, double-tap-seek with a movement-tolerance guard, `RotateHint`, and safe-area-anchored bars using `--sa-*` and a measured `--watch-bar-h`. The z-index bands are centralized in `watchLayers.js`.
- The sync path is subtle and correctness-critical: `useSyncPlay` (host-authority shared timeline, buffer-aware seeks, `applyingRef` authoring guard, drift telemetry) is driven through `SyncBridge` inside `Player.jsx`, and seeks are routed through the media element via `seekBridgeRef` so guest-follow authoring runs. Re-implementing any of this risks re-introducing the chase-loop / spurious-authoring bugs the current code documents fighting.
- LiveKit lifecycle (`useLiveKit({partyId, enabled})`) is connection-managed and must not remount on rotation.

Therefore the mobile Watch layer is a **presentation reuse**, not new code. Two consequences the builder must honor:
1. Render Party via the **shared `PartyRoute`** (§2.2) so it is mount-stable across the `usePhone()` flip.
2. Any mobile watch-screen polish (e.g. restyling `MobileBottomBar`, the `RotateHint` chip, the lobby `LobbyAVBar`) is done **inside the existing components**, additively, keeping the desktop branches intact. Do not fork Party into `mobile/`.

The **lobby** (`session.stage === 'lobby'`) already renders the embedded `<Library>` mirror experience and self-adapts; leave its architecture alone. If its poster grid needs mobile spacing tweaks, adjust within `Library.jsx`'s existing `mobile` branches.

### 2.5 State, transitions, back behavior
- Screen-to-screen nav uses `navigate('/library'|'/discover'|'/downloads'|'/party/new')`. The tab bar reflects the current `path`.
- Android hardware back / iOS edge-swipe map to browser history (works for free with `pushState`). Do **not** attach horizontal swipe handlers to the root — it would fight iOS edge-back (the Watch code already avoids this deliberately).
- Sheets (Join, filters, season picker) are in-screen overlays, not routes; closing them is a local state toggle, not a history pop.

---

## 3. Screen Inventory

Tab bar visible on Home / Browse / Downloads. Login = no tab bar, no back. Watch = immersive, no tab bar (its own chrome).

### 3.1 Login — `mobile/screens/Login.jsx`
Reuses `useAuth().login`. Full-bleed dark with the ambient radial glow (port from desktop `Login.jsx`). Wordmark, `display` H1 "Welcome back", subtitle "Sign in with your Jellyfin account", two fields (username/password) + primary white pill button with spinner state.
- Inputs **must be `font-size: 16px`** (desktop uses 15 → would zoom on iOS). Fields ≥ 48px tall, `autoComplete` set, `autoCapitalize="none"` on username.
- On success, the existing `Router` `returnTo` effect handles navigation — keep `onSuccess` as a no-op fallback like desktop.

### 3.2 Home — `mobile/screens/Home.jsx`
The phone home = library landing + "Downloading now". Reuses `/api/library/home` (`resume`, `nextUp`, `views`), `/api/library/latest`, and `useDownloads` (port the hook from `Library.jsx`).
- **Top bar:** greeting + avatar (initials) → tap opens an account sheet with Sign out (`logout`). A "Join" affordance opens `JoinSheet`.
- **Content:** vertical stack of **swipeable rails** (`ui/Rail.jsx`): Continue watching (16:9 stills w/ progress bar), Recently added (2:3 posters, NEW badge), Downloading now (live progress cards — only when `arriving.length > 0`), Next up, Libraries (16:9 view cards).
- Tapping a poster → detail. Detail's "Watch" → `navigate('/party/new?itemId=${id}')` (starts a party, exactly like desktop `pick()`), OR drills into series/season via `/api/library/items/:id/children`.
- Rails: horizontal scroll with `scroll-snap`, **no hover arrows** — swipe only. Keep the mono count label.

### 3.3 Browse (Discover) — `mobile/screens/Browse.jsx`
Mobile presentation of `FindDownload.jsx`: search + discover + **season chooser** + **release picker**. Reuses `/api/servarr/search`, `/releases`, `/request`, `/request-season`, `useTorrents`, `useFailingCount`.
- **Top bar:** a search field (16px) with the mono placeholder; debounced query hits `/api/servarr/search`.
- **Results:** poster grid (2:3, `minmax(118px,1fr)` like Library's mobile wall). Movie card → request; series card → **season chooser sheet** (`ui/Sheet.jsx`) listing seasons with request-season actions.
- **Release picker:** when manual grab is offered, a bottom sheet lists releases (title, size, seeds, quality via mono meta) with a request action. Sheets are ≥44px rows, scrollable, safe-area padded.
- A live badge/affordance links to Downloads when items are grabbing (reuse the `active`/`failingCount` counts).

### 3.4 Downloads — `mobile/screens/Downloads.jsx`
Mobile presentation of `Downloads.jsx`: the qBittorrent queue. Reuses `useTorrents`, `useFailingCount`, and the pause/resume/delete endpoints desktop already calls.
- List of download rows: poster thumb, `displayTitle`/`subtitle`, live progress bar (brand-green→periwinkle), mono `%`, `↓ speed`, seeds/peers. Failing items flagged with the red alert treatment.
- Per-row actions (pause/resume/remove) via a trailing overflow or a swipe-reveal action row — **actions must have visible affordances** (no hover reveal). ≥44px targets.
- Empty state when Servarr unconfigured/unreachable (degrades to `[]`).

### 3.5 Watch / Party — reuse `pages/Party.jsx` (§2.4)
Immersive. No tab bar. No app top bar. Its own auto-hiding chrome (`MobileBottomBar`, `MobileCameraStrip`, `ChatSheet`, `RoomControls`, `RotateHint`) already exists and is phone-tuned. Lobby stage reuses the embedded `<Library>` mirror. QR/code join lands here via `/party/:code`.

### 3.6 Shared shell — `MobileApp.jsx` + `TabBar.jsx`
- `MobileApp` renders the ambient backdrop, `<GlassDefs/>` is already global, the active screen, and `<TabBar/>` (except on `/login`).
- `TabBar`: floating glass pill, `position: fixed; left/right: 12px; bottom: calc(var(--sa-b) + 10px)`. Three tabs — **Home**, **Browse**, **Downloads** — plus a prominent **center "Party"** action (start/join) that is visually elevated (brand-gradient circle) since starting a watch party is the app's primary verb. Tab active state = brand accent + filled icon; inactive = `T.dim`. Downloads tab shows the active-count dot (brand-green) / failing dot (red), mirroring the desktop sidebar `NavRow` badges. Labels = `label` token. Every tab ≥ 44×44.
- Toasts: mount the existing `PartyContext` toast pattern where relevant; for shell screens a lightweight top toast at `Z.toast` band.

---

## 4. PWA Plan (hide browser chrome)

Goal: "Add to Home Screen" → launches standalone, **no address/tab bar**, dark status bar, our icon.

### 4.1 Serving (verified)
- **Dev:** Vite serves `client/` + anything in `client/public/` at root. **Prod:** `server/index.js` does `express.static(clientDist)` then an SPA `*` fallback that excludes `/api|/socket.io|/jellyfin|/livekit`. Vite copies `client/public/*` into `dist/` root at build.
- **Therefore:** put manifest + icons in **`app/client/public/`** (create it — it does not exist yet). They are then served **same-origin** at `/manifest.webmanifest`, `/icon.svg`, `/icon-192.png`, `/icon-512.png`, `/apple-touch-icon.png` in both dev and prod, and `express.static` returns them with correct MIME before the SPA fallback runs. No server code change needed.

### 4.2 `app/client/public/manifest.webmanifest`
```json
{
  "name": "Watchparty",
  "short_name": "Watchparty",
  "description": "Watch together, in sync.",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "display_override": ["standalone", "fullscreen"],
  "orientation": "any",
  "background_color": "#08080a",
  "theme_color": "#08080a",
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" },
    { "src": "/icon.svg", "type": "image/svg+xml", "sizes": "any", "purpose": "any" }
  ]
}
```
`start_url: "/"` is correct: the `Router` sends `/` → `/library` when authed, `/login` otherwise.

### 4.3 `index.html` `<head>` additions
Current head has only the viewport (`width=device-width, initial-scale=1.0, viewport-fit=cover`) and an inline SVG favicon. **Keep the viewport exactly** — it already has `viewport-fit=cover` and does **not** set `user-scalable=no` (per constraint, do not add it). Add:

```html
<meta name="theme-color" content="#08080a" />
<meta name="apple-mobile-web-app-capable" content="yes" />
<meta name="mobile-web-app-capable" content="yes" />
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent" />
<meta name="apple-mobile-web-app-title" content="Watchparty" />
<link rel="manifest" href="/manifest.webmanifest" />
<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
<link rel="icon" type="image/svg+xml" href="/icon.svg" />
```
- `black-translucent` puts content under the status bar → **must** be paired with `--sa-t` padding on top bars (already defined in `styles.css`). This is what removes the visible bar and gives the edge-to-edge app feel.
- iOS ignores manifest icons for the home-screen glyph and uses `apple-touch-icon` (**PNG required**, 180×180). Android/Chrome use the manifest PNGs (192/512) + maskable.

### 4.4 Icons (generate locally, no remote fetch)
Author one SVG mark and rasterize it — do **not** fetch remote art. The mark matches the existing brand: a rounded-square in the app gradient with a play glyph.

`app/client/public/icon.svg` (source):
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#3ecf7e"/><stop offset=".5" stop-color="#6a8bff"/><stop offset="1" stop-color="#d16aff"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="112" fill="#0b0d10"/>
  <rect x="40" y="40" width="432" height="432" rx="96" fill="url(#g)"/>
  <path d="M212 176 L360 256 L212 336 Z" fill="#0b0d10"/>
</svg>
```
Rasterize to `icon-192.png`, `icon-512.png`, and `apple-touch-icon.png` (180×180, **no transparency** — iOS masks it, so fill the full square). Rasterization options (pick what's available in the toolchain, all local): `resvg icon.svg -w 512 icon-512.png`, or `rsvg-convert`, or a headless-Chrome screenshot of the SVG, or a tiny Node `sharp`/`@resvg/resvg-js` script. Commit the PNGs to `public/`. iOS `apple-touch-icon` must be a real PNG — an SVG there is unreliable.

### 4.5 Fonts note
`styles.css` pulls Hanken Grotesk / JetBrains Mono from Google Fonts (remote). This is fine for the live app (not an Artifact) and already in place. For installed-PWA resilience the system fallbacks already declared keep the UI legible offline; **self-hosting the fonts is optional** and out of scope here.

---

## 5. Safari / Chrome rules (builders MUST follow)

1. **Viewport height = `100dvh`, never `100vh`.** The shell is `position: fixed; inset: 0; height: 100dvh`. `dvh` tracks the *visible* viewport as the URL bar collapses/expands, so the layout does not jump. (Watch already does this — match it everywhere.)
2. **Safe areas via `env()`.** The tokens `--sa-t/-r/-b/-l` already exist in `styles.css`. Top bars pad `var(--sa-t)`; the tab bar and any bottom-anchored bar pad `var(--sa-b)`; landscape uses `--sa-l/--sa-r`. Never hardcode notch offsets.
3. **No-zoom inputs.** Every `<input>/<textarea>/<select>` is **≥16px** font-size. (Fix Login's 15px.) Do not add `user-scalable=no`.
4. **Touch targets ≥ 44×44px.** Tab items, sheet rows, download actions, transport buttons. No 38px desktop buttons on phone.
5. **No hover-only affordances.** Rails swipe (kill the desktop hover arrows on phone). Download row actions have persistent or swipe-revealed visible controls. Card feedback uses `:active { transform: scale(.97) }`, not `:hover`.
6. **Momentum + contained scroll.** The single scroll region gets `-webkit-overflow-scrolling: touch` and `overscroll-behavior: contain`. The `<body>`/shell never scrolls horizontally — wide content (rails, release lists) scrolls inside its own `overflow-x: auto` container.
7. **Kill tap artifacts.** Add global mobile rules to `styles.css` (additive, does not affect desktop): `-webkit-tap-highlight-color: transparent` and `touch-action: manipulation` on interactive roots (the Watch stage already sets `touch-action: manipulation`; extend the pattern to shell buttons to remove the 300ms delay). Do **not** put `touch-action: none` anywhere that would block scroll or iOS edge-back.
8. **Don't fight system gestures.** No root-level horizontal swipe handlers (breaks iOS edge-back). Let history/`pushState` drive back.
9. **Fixed overlays use `dvh`/`dvw` + `--sa-*`**, mirroring the Watch `ChatSheet`/`MobileCameraStrip` (bottom anchored via `calc(var(--sa-b) + …)`), so nothing hides under Safari's collapsing toolbars or the home indicator.
10. **Images:** posters `object-fit: cover`, `max-width: 100%`, and reuse the `failedArt` 404-guard so a missing poster is never re-requested (prevents request storms on scroll).

Suggested additive block for `styles.css` (guarded so desktop is untouched):
```css
@media (pointer: coarse) {
  * { -webkit-tap-highlight-color: transparent; }
  input, textarea, select { font-size: 16px; }  /* iOS anti-zoom */
}
```

---

## 6. Build order (suggested for the implementation agents)
1. `mobile/theme.js` + `ui/{Icon,Poster,Rail,Sheet,TopBar,Skeleton}.jsx` (shared kit).
2. `App.jsx` device branch + `PartyRoute` extraction + `MobileApp` + `TabBar` (shell wired, screens stubbed).
3. `screens/Login.jsx` → `screens/Home.jsx` → `screens/Browse.jsx` → `screens/Downloads.jsx`.
4. `index.html` meta + `public/` manifest + icons (PWA).
5. Watch: verify `PartyRoute` mount-stability across rotation; apply any additive mobile polish inside existing Party/Player components only.
6. Global `styles.css` mobile block (§5). Verify desktop unchanged at every step.

## 7. Definition of done
- On a phone: install to home screen → launches standalone, no browser chrome, dark status bar, our icon; bottom tab bar navigates Home/Browse/Downloads; starting/joining a party enters the existing synced watch screen with cameras + chat; QR/code join resolves to `/party/:code`.
- On desktop/tablet: pixel-identical to today (no diff in rendered desktop pages).
- No engine rebuilt: sync, LiveKit, Servarr, auth all go through the existing hooks/API verbatim.
```
