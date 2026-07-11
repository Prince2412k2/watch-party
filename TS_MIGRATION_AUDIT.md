# TypeScript Migration Audit — `app/client/src/`

## TL;DR

The codebase is `.tsx`/`.ts` files with **JavaScript semantics**. `strict: false`, zero `import type`, 130+ explicit `any` annotations, 53 untyped `useRef()`, 152 untyped `useState()`, 84 exported functions missing return types, and an active `types-relaxed-jsx.d.ts` that disables JSX prop checking. `contract.ts` (the native boundary) uses JSDoc instead of TS interfaces.

---

## 1. tsconfig.json — Root Cause

```json
"strict": false
```

This disables `strictNullChecks`, `noImplicitAny`, `strictFunctionTypes`, etc. Everything compiles without complaint. This is the #1 thing to flip.

Also: `skipLibCheck: true` — skips type errors in `node_modules` definitions.

---

## 2. types-relaxed-jsx.d.ts — Active Sabotage

This file (`src/types-relaxed-jsx.d.ts:1-15`) **globally weakens JSX typing**:

- `LibraryManagedAttributes<C, P> = Partial<P>` — makes ALL component props optional everywhere, defeating prop-checking
- `CSSProperties { [key: string]: any }` — allows any CSS property value

**This file should be deleted** before enabling strict mode.

---

## 3. contract.ts — JSDoc Instead of TS Interfaces

`src/native/contract.ts` defines `MediaBackend`, `BufferedRanges`, `DownloadRecord`, `OfflineRecord` as **JSDoc `@typedef`** comments (lines 14-35, 89-107), not TypeScript interfaces/types. These types are invisible to the TS compiler. The `IPC` and `EVENTS` constants are untyped objects.

---

## 4. Per-File Breakdown — `any` Density

| File | `: any` count | `as any` | Untyped params | Untyped useRef | Severity |
|------|:---:|:---:|:---:|:---:|---|
| **components/Player.tsx** | 18 | 5 | 0 | 12 | 🔴 Critical |
| **mobile/screens/Browse.tsx** | 20 | 0 | 0 | 2 | 🔴 Critical |
| **mobile/screens/Downloads.tsx** | 16 | 0 | 0 | 1 | 🔴 Critical |
| **pages/FindDownload.tsx** | 16 | 0 | 0 | 2 | 🔴 Critical |
| **pages/Library.tsx** | 16 | 0 | 0 | 3 | 🔴 Critical |
| **pages/Party.tsx** | 5 | 1 | 0 | 5 | 🟡 High |
| **pages/Downloads.tsx** | 9 | 0 | 0 | 1 | 🟡 High |
| **mobile/screens/Home.tsx** | 13 | 0 | 0 | 1 | 🟡 High |
| **lib/ui.tsx** | 8 | 0 | 1 | 0 | 🟡 High |
| **sync/syncCore.ts** | 5 | 0 | 1 | 0 | 🟡 High |
| **native/offline/reconcile.ts** | 10 | 0 | 0 | 0 | 🟡 High |
| **components/RoomControls.tsx** | 2 | 0 | 0 | 0 | 🟢 Medium |
| **components/Chat.tsx** | 2 | 0 | 0 | 0 | 🟢 Medium |
| **components/CameraGrid.tsx** | 1 | 0 | 0 | 0 | 🟢 Medium |
| **components/CameraTile.tsx** | 1 | 0 | 0 | 2 | 🟢 Medium |
| **components/Dock.tsx** | 1 | 0 | 0 | 0 | 🟢 Medium |
| **components/DownloadDetail.tsx** | 3 | 0 | 0 | 0 | 🟢 Medium |
| **context/AuthContext.tsx** | 1 | 0 | 0 | 0 | 🟢 Medium |
| **context/PartyContext.tsx** | 1 | 0 | 0 | 1 | 🟢 Medium |
| **hooks/useLiveKit.ts** | 1 | 0 | 0 | 0 | 🟢 Medium |
| **hooks/usePushToTalk.ts** | 1 | 0 | 0 | 0 | 🟢 Medium |
| **hooks/useSyncPlay.ts** | 2 | 0 | 0 | 12 | 🟢 Medium |
| **hooks/useServerClock.ts** | 0 | 0 | 1 | 2 | 🟢 Medium |
| **hooks/useFailingDownloads.ts** | 0 | 0 | 1 | 0 | 🟢 Medium |
| **hooks/useTorrents.ts** | 0 | 0 | 1 | 1 | 🟢 Medium |
| **lib/format.ts** | 0 | 0 | 6 | 0 | 🟢 Medium |
| **sync/bufferSeek.ts** | 0 | 0 | 5 | 0 | 🟢 Medium |
| **sync/syncCore.ts** | 0 | 0 | 1 | 0 | 🟢 Medium |
| **router.ts** | 0 | 0 | 1 | 0 | 🟢 Medium |
| **native/MpvBackend.ts** | 2 | 0 | 0 | 0 | 🟢 Medium |
| **native/ipc.ts** | 1 | 0 | 0 | 0 | 🟢 Medium |
| **native/env.ts** | 0 | 1 | 0 | 0 | 🟢 Medium |
| **native/offline/\*.tsx** | 3 | 0 | 0 | 0 | 🟢 Medium |
| **mobile/ui/\*.tsx** | 8 | 0 | 0 | 1 | 🟢 Medium |
| **mobile/TabBar.tsx** | 3 | 0 | 0 | 0 | 🟢 Medium |
| **mobile/JoinSheet.tsx** | 1 | 0 | 0 | 0 | 🟢 Medium |
| **mobile/MobileApp.tsx** | 1 | 0 | 0 | 0 | 🟢 Medium |
| **mobile/screens/Login.tsx** | 1 | 0 | 0 | 0 | 🟢 Medium |
| **pages/Lobby.tsx** | 1 | 0 | 0 | 0 | 🟢 Low |
| **pages/Login.tsx** | 1 | 0 | 0 | 0 | 🟢 Low |
| **glass.tsx** | 1 | 0 | 0 | 0 | 🟢 Low |
| **mirror.ts** | 1 | 0 | 0 | 0 | 🟢 Low |

---

## 5. Global Patterns

| Pattern | Count | Notes |
|---------|:-----:|-------|
| Explicit `: any` | **130+** | Pervasive across every layer |
| `as any` assertion | **8** | 5× `VPlayer.useMedia() as any`, 1× `useHideSelf() as any`, 1× `window.__TAURI__`, 1× `MpvBackend.ts` |
| Untyped function params | **20+** | `lib/format.ts` (6), `sync/bufferSeek.ts` (5), hooks (5), `router.ts` (1), `lib/ui.tsx` (1) |
| Untyped `useRef()` | **53** | Zero have type parameters |
| Untyped `useState()` | **152** | Zero have type parameters (rely on inference from `null`/`false`/`[]` initial values) |
| `import type` usage | **0** | Zero out of 222 imports — no type-only imports anywhere |
| `React.FC` usage | **0** | Consistent: all components use `function` declarations |
| Missing return types | **84** | Every exported function in the codebase |
| `@ts-ignore`/`@ts-nocheck` | **0** | None found |
| `require()` calls | **0** | Clean ESM |
| `.ts` extensions in imports | **3** | `Player.tsx:13`, 2 in test files |

---

## 6. Import Dependency Map

### Top-level entry points
```
main.tsx → App.tsx → router.ts
                   → context/AuthContext.tsx
                   → context/PartyContext.tsx
                   → pages/{Party,Library,FindDownload,Downloads,Login,Lobby}.tsx
                   → mobile/MobileApp.tsx
```

### Context providers (type surface — what flows through)
```
AuthContext.tsx
  exports: AuthProvider({children}: any), useAuth()
  state: user: null (untyped)

PartyContext.tsx
  exports: PartyProvider({children, userId}: any), useParty()
  state: entire reducer state (inferred from reducer, no explicit types)
  provides: ~30+ values via context — all untyped at the call site
```

### Heavy component trees (most `any` density)
```
Party.tsx
  └→ HlsPlayer → Player.tsx (HlsVideo, SyncBridge, TopBar, DesktopControlBar, MobileBottomBar, SettingsMenu, Scrubber, VolumeControl, IconBtn, etc.)
  └→ CameraGrid/Dock → CameraTile
  └→ RoomControls → JoinQR
  └→ Chat

FindDownload.tsx
  └→ SearchBar, ResultGrid, ResultCard, DetailView, SeasonChooser, OptionsDialog, ReleasePicker, PopularRail, etc.
  (20 internal sub-components, all `: any` props)

Library.tsx
  └→ HomeView, PosterCard, StillCard, ViewCard, Rail, Details, GridView, Sidebar, TopBar, etc.
  (20+ internal sub-components, all `: any` props)

mobile/screens/Browse.tsx
  └→ 20 internal sub-components, all `: any` props

mobile/screens/Downloads.tsx
  └→ 16 internal sub-components, all `: any` props

mobile/screens/Home.tsx
  └→ 13 internal sub-components, all `: any` props
```

### Hook dependency chain
```
useSyncPlay.ts → depends on: createTransportIntent (sync/transportIntent.ts)
                                    predictPosition, decideSyncAction (sync/syncCore.ts)
                                    waitForSeeked, isBuffered, ensureHlsLoad, etc. (sync/bufferSeek.ts)
useLiveKit.ts → LiveKit room SDK
useSocket.ts → socket.io client
useTorrents.ts → useSocket, api.ts
usePushToTalk.ts → LiveKit localParticipant
useServerClock.ts → useSocket
useFailingDownloads.ts → useTorrents
```

### Native boundary
```
native/contract.ts (JSDoc types — MediaBackend, DownloadRecord, OfflineRecord)
  ↑ imported by: Player.tsx, MpvBackend.ts, ipc.ts, offline/reconcile.ts, useOffline.ts, DownloadButton.tsx

native/ipc.ts → Tauri invoke/event API
native/MpvBackend.ts → implements MediaBackend duck-type
native/offline/reconcile.ts → pure functions operating on Map<string, any>
```

---

## 7. Recommended Migration Order

1. **Delete `types-relaxed-jsx.d.ts`** — removes the global Partial-prop escape hatch
2. **Enable `strict: true`** in tsconfig (will surface ~200+ errors to fix)
3. **Convert `contract.ts` JSDoc → real TS interfaces** (`MediaBackend`, `DownloadRecord`, `OfflineRecord`)
4. **Type `lib/format.ts`** — 6 pure functions, zero dependencies, quick win
5. **Type `lib/ui.tsx`** — 8 shared components, everything imports these
6. **Type hooks** — `useServerClock`, `useFailingDownloads`, `useTorrents` first (small), then `useSyncPlay` (complex), then `useLiveKit`
7. **Type `sync/` modules** — `bufferSeek.ts`, `syncCore.ts`, `transportIntent.ts` — pure logic, testable
8. **Type contexts** — `AuthContext`, `PartyContext` — define the state shapes
9. **Type page components** — `Login`, `Lobby` first (tiny), then `Party`, `Library`, `FindDownload`, `Downloads`
10. **Type mobile screens** — largest `any` density by file count
11. **Type `Player.tsx`** — largest single file, 18 `any` + 5 `as any` + 12 untyped `useRef` — save for last

---

## 8. Quick Wins (< 30 min each)

| Task | Files | Impact |
|------|-------|--------|
| Delete `types-relaxed-jsx.d.ts` | 1 | Enables real prop checking globally |
| Type `lib/format.ts` | 1 | 6 pure functions, no deps |
| Type `native/offline/format.ts` | 1 | 3 pure functions |
| Type `sync/transportIntent.ts` | 1 | 1 factory function |
| Type `router.ts` | 1 | 1 function |
| Add return types to all hooks | 8 files | ~15 functions |
| Convert `contract.ts` JSDoc → TS | 1 | Enables native boundary typing |
| Type `useRef()` calls | 12 files | 53 refs — mostly `<HTMLDivElement>` / `<HTMLVideoElement>` / `<HTMLInputElement>` |
| Add `import type` for type-only imports | ~30 files | Tree-shaking + clarity |
