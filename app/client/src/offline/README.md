# Browser downloads

The **Saved** page manages downloads and playback cache. Movie and episode details
offer Download in secure browsers with service workers, IndexedDB and OPFS. Downloading
pins the media before fetching bytes; cached chunks are reused. Pause keeps the
pin. Cancel download discards its OPFS file and keeps any remaining IndexedDB
playback cache; Remove deletes metadata, cached ranges, captions and the OPFS file.
Clear cache protects downloads, including incomplete
ones, and reports any cache still being played in another tab. Cache expires after
seven days without use; cleanup runs when the app/worker starts and hourly while
the app is open.

Explicit downloads live in **one MP4 per movie in OPFS**, inside the app-owned
`watchparty-downloads-v1` directory. File names include the movie/series title and
a unique generation. A dedicated worker writes three concurrent, bounded 2 MiB
ranges through `FileSystemSyncAccessHandle`; it flushes and closes each range
before publishing its index. Sparse file length alone never means complete.
Pause drains pending writes, and Resume requests only ranges that are missing.

**Playback cache stays in IndexedDB** as 2 MiB chunks, alongside title/source/
revision metadata, downloaded-range indexes, small poster images and WebVTT
captions. Promoting a cache copies existing ranges into the MP4 and deletes their
duplicate IndexedDB bytes after the file write succeeds. Existing full and partial
downloads migrate the same way on opening the app, including while offline, without
fetching their stored ranges again. A manually paused download stays paused.

Inventory on opening removes orphan MP4s from the app's own directory, preserves
other accounts' files and active writers, and repairs missing/truncated-file
metadata so Resume can restore absent ranges. Generation checks and shared file/
transfer locks prevent late writes from recreating removed downloads. IndexedDB
read/modify/write requests are issued inside callbacks to keep transactions active
in Safari; abort errors retain their actual cause instead of a generic message.

The Saved page uses actual stored-byte
counts, compact poster rows, and menus for secondary actions. JavaScript localStorage holds only a remembered account ID/name
for reopening the offline library. It contains no movies, tokens or privileges.
Logging out hides local media; signing back into the same account restores access.

The authenticated server endpoint accepts converted H.264 8-bit SDR/AAC MP4
sources. It proxies original byte ranges without transcoding, pins source identity,
file length and an upstream ETag/Last-Modified revision, and rejects changed files
before their bytes can enter an existing download. Completed OPFS downloads use a
`File`-backed blob URL directly in the player, revoked when playback unmounts.
Partial downloads and playback cache use service-worker MP4 range responses,
reading known OPFS ranges first, then IndexedDB, then the network. The server shares a short-lived, authenticated
source snapshot between ranges, while validating the revision of every response.

Party playback keeps the existing Socket.IO timeline and local correction logic.
Each participant independently uses their local file or cached ranges for the shared source.
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
the service worker validates and imports its completed ranges into OPFS using one
asynchronous writable for the batch (sync handles require a dedicated worker).
Range metadata is published only after the writable closes successfully.
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
OPFS migration, sparse-file integrity, orphan/missing-file repair, transaction
error causes, and file/metadata/chunk/caption deletion with late writes. Browser
smoke checks should include offline reload/seek/captions, pause/resume, cache clear
with a pinned movie, download completion after closing the Chromium app page,
interrupted-download recovery, camera/mic sharing from Saved, and two party participants playing saved media through the
same play/pause/seek commands without upstream media requests. Physical Safari/iOS
testing is still required; this cloud environment runs Chromium on Linux.
