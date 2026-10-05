# Native Cache v3

v3 is an invalidation, not a relabeling migration. Earlier media caches were
keyed only by item ID and some HTTP writers accepted error bodies and ignored
ranges. There is no trustworthy way to infer their server, selected media source,
or byte integrity after the fact.

- Production media now lives in `media-cache/v3/<sha256-backend-url>/`.
- Explicit media source IDs use separate hashed keys, never the default item's
  bytes. Source-specific entries do not masquerade as default offline downloads.
- Offline metadata uses `v3-<sha256-backend-url>-offline_manifest.json`.
- Legacy unscoped media and manifests are not imported, deleted, or advertised
  as playable. Previously downloaded titles must be downloaded again. Old files
  remain on disk for deliberate cleanup; current-origin cache clearing does not
  remove these quarantined legacy files or another origin's downloads.
- Artwork now keys relative URLs by their resolved absolute URL. Legacy
  relative-URL artwork is not trusted across origins and is fetched again;
  ordinary artwork eviction can reclaim the old files.

Media sidecars now record `retention` (`cache` or `download`) separately from
byte completeness, plus readable `media` metadata (title, series/season/episode,
item/source identity, container, poster and runtime when available). Pressing
Download persists retention before fetching and reuses the same validated ranges.
Partial downloads survive cleanup/restarts and reappear paused with Resume/Cancel.
Cancel releases download retention; the remaining chunks become playback cache.
Explicit Remove deletes media, sidecar and interrupted sidecar temporary files;
failed deletions keep ownership metadata and surface an error for retry.

Fully watched new entries remain cache, not downloads. Temporary entries expire
after seven days without access; startup, completed fills and an hourly timer run
cleanup. Active HTTP/read-ahead work is protected, rather than every entry ever
opened in the process. Clear Cache consults persisted retention, discovers orphan
`.data`/`.meta.json.tmp` files and cancels temporary transfers before deletion.

Older completed v3 entries lack reliable download intent (the old offline list
also included fully watched titles). These are conservatively preserved as
existing downloads; no historical intent is invented. Unreadable ownership
metadata is preserved, and quarantined pre-v3/other-origin files still require
deliberate cleanup rather than destructive automatic migration.

Explicit v3 downloads survive logout, origin switches, and automatic
TTL/size eviction. Returning to the same backend restores them. Explicit removal
and confirmed per-item 404/410 reconciliation retain their existing deletion
policy; transient network/authentication failures do not delete downloads.

HTTP cache writes require exact, unencoded 206 ranges and exact body lengths.
Foreground/read-ahead requests use at most 1 MiB; downloads retain at most 8 MiB.
URL minting, connection/headers, and whole-body reads have separate 30-second
deadlines. Cancellation closes active HTTP clients and rejects late signed URLs.

File handles are held only during serialized I/O, and session teardown disposes
the old store. Eviction protects explicit downloads and active transfers. This is not a hard process-wide disk
quota, especially with protected offline downloads and multiple origins. A true
cross-origin quota/lease-based live-entry eviction policy is a separate change.

The API does not expose a persistent media revision or strong validator. v3
isolates origins and explicitly selected sources and checks total lengths, but
cannot detect an upstream file replaced in place with different bytes of the
same length. That requires an upstream revision/ETag contract or content hashes.
