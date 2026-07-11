# TypeScript Migration Progress

## Status: Complete

The web client now enforces strict TypeScript without compiler escape hatches.

| Acceptance gate | Result |
|---|---|
| `strict: true` | ✅ |
| `types-relaxed-jsx.d.ts` removed | ✅ |
| `@ts-nocheck` in `app/client/src` | **0** |
| Explicit `any` / `as any` in `app/client/src` | **0** |
| Strict `tsc --noEmit` errors | **0** |
| Strictly typed tests | **24/24 passing** |
| Production Vite build | ✅ |
| Raw `Response.json()` call sites | **1 centralized unknown boundary** |

## Completed Areas

- Shared party, authentication, playback, Jellyfin media, torrent, mirror, and native contracts
- Player, HLS quality selection, audio/subtitle tracks, upload handling, and sync bridge
- Desktop Library, Discover/Find Download, Downloads, Party, Login, and Lobby pages
- Mobile Home, Browse, Downloads, Login, Watch, navigation, shell context, and shared UI
- Party and authentication contexts
- Playback synchronization, torrent polling, LiveKit integration, and supporting hooks
- Tauri IPC, mpv backend, offline download reconciliation, and offline UI
- Runtime guards for key external JSON boundaries introduced during the migration

## Verification

Run from `app/client`:

```bash
npm run typecheck -- --pretty false
npm test
npm run build
```

All three commands pass. Vite reports only the existing large-chunk advisory; it is
not a compilation or type-safety failure.
