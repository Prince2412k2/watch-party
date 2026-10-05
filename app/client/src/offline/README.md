# Browser downloads

The **Saved** page manages downloads and playback cache. Movie and episode details
offer Download in secure browsers with service workers and IndexedDB. Downloading
pins the media before fetching bytes; cached chunks are reused. Pause keeps the
pin, Cancel download turns it into cache, and Remove deletes metadata, chunks and
captions in one transaction. Clear cache protects downloads, including incomplete
ones, and reports any cache still being played in another tab. Cache expires after
seven days without use; cleanup runs when the app/worker starts and hourly while
the app is open.

Media bytes live in IndexedDB as 2 MiB chunks, alongside title/series metadata and
WebVTT captions. JavaScript localStorage holds only a remembered account ID/name
for reopening the offline library. It contains no movies, tokens or privileges.
Logging out hides local media; signing back into the same account restores access.

The authenticated server endpoint accepts converted H.264 8-bit SDR/AAC MP4
sources. It proxies original byte ranges without transcoding, pins source identity,
file length and an upstream ETag/Last-Modified revision, and rejects changed files
before their bytes can enter an existing download. The worker serves seekable local
MP4 ranges and only fetches missing chunks. Generation checks prevent removed
files from being resurrected by transfers that finish late.

Party playback keeps the existing Socket.IO timeline and local correction logic.
Each participant independently uses their local chunks for the shared source.
Parties still need server connectivity. Non-default shared audio tracks and titles
that have not been converted retain HLS playback because browsers cannot reliably
switch the audio tracks in a static MP4. Standalone saved playback works offline.
Text captions are saved; bitmap subtitles are not converted by this download path.

The service worker caches only the public app shell and build assets, never API
sessions, Jellyfin responses or LiveKit signaling. It serves local files only for
the active account. The browser may evict storage even after a persistence request,
and mobile operating systems may stop a download when the app is suspended. Keep
the app open to download; paused transfers can resume using existing chunks.

Validation: `npm run typecheck`, `npm test`, `npm run build` in `app/client`, and
`npm test` in `app`. Storage tests cover pin promotion, TTL/account isolation,
range validation, and metadata/chunk/caption deletion with late writes. Browser
smoke checks should include offline reload/seek/captions, pause/resume, cache clear
with a pinned movie, and two party participants playing saved media through the
same play/pause/seek commands without upstream media requests. Physical Safari/iOS
testing is still required; this cloud environment runs Chromium on Linux.
