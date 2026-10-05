# Browser downloads

The **Saved** page manages downloads and playback cache. Movie and episode details
offer Download in secure browsers with service workers and IndexedDB. Downloading
pins the media before fetching bytes; cached chunks are reused. Pause keeps the
pin, Cancel download turns it into cache, and Remove deletes metadata, chunks and
captions in one transaction. Clear cache protects downloads, including incomplete
ones, and reports any cache still being played in another tab. Cache expires after
seven days without use; cleanup runs when the app/worker starts and hourly while
the app is open.

Media bytes live in IndexedDB as 2 MiB chunks, alongside title/series metadata,
small poster images and WebVTT captions. The Saved page uses actual stored-byte
counts, compact poster rows, and menus for secondary actions. JavaScript localStorage holds only a remembered account ID/name
for reopening the offline library. It contains no movies, tokens or privileges.
Logging out hides local media; signing back into the same account restores access.

The authenticated server endpoint accepts converted H.264 8-bit SDR/AAC MP4
sources. It proxies original byte ranges without transcoding, pins source identity,
file length and an upstream ETag/Last-Modified revision, and rejects changed files
before their bytes can enter an existing download. The worker serves seekable local
MP4 ranges and only fetches missing chunks. Generation checks prevent removed
files from being resurrected by transfers that finish late. Foreground downloads
fetch three ranges concurrently. The server shares a short-lived, authenticated
source snapshot between ranges, while validating the revision of every response.

Party playback keeps the existing Socket.IO timeline and local correction logic.
Each participant independently uses their local chunks for the shared source.
Parties still need server connectivity. Non-default shared audio tracks and titles
that have not been converted retain HLS playback because browsers cannot reliably
switch the audio tracks in a static MP4. Standalone saved playback works offline.
Text captions are saved; bitmap subtitles are not converted by this download path.

The service worker caches only the public app shell and build assets, never API
sessions, Jellyfin responses or LiveKit signaling. It serves local files only for
the active account. The browser may evict storage even after a persistence request,
and mobile operating systems may stop an ordinary worker download when suspended.

Chromium browsers with **Background Fetch** can keep an explicitly requested
download running after the page closes. The page starts the browser-managed job;
the worker validates and imports its completed ranges, one chunk at a time.
Existing watched chunks are omitted, and playback can use background ranges that
have already arrived. If permission, quota, or browser limits prevent this, the
three-range worker queue remains available. Background responses temporarily
require extra storage before import, so low available quota also selects the queue.
Pause/Cancel/Remove abort the browser job; generation and account checks protect
against late completions and simultaneous tabs share an initiation lock.

**Safari/iPhone and Firefox do not implement Background Fetch.** Their downloads
may pause when the app closes or the screen locks. Unfinished download intent
resumes automatically on reopening, returning to the foreground, or regaining a
connection. An explicit Pause stays paused. This is not an iOS background-transfer
guarantee; native apps are needed for dependable transfers while suspended.

Validation: `npm run typecheck`, `npm test`, `npm run build` in `app/client`, and
`npm test` in `app`. Storage tests cover pin promotion, TTL/account isolation,
range validation, bounded concurrent downloads, Background Fetch import/fallback,
and metadata/chunk/caption deletion with late writes. Browser
smoke checks should include offline reload/seek/captions, pause/resume, cache clear
with a pinned movie, download completion after closing the Chromium app page,
interrupted-download recovery, camera/mic sharing from Saved, and two party participants playing saved media through the
same play/pause/seek commands without upstream media requests. Physical Safari/iOS
testing is still required; this cloud environment runs Chromium on Linux.
