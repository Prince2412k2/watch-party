# Media Converter

A persistent, Dockerized MP4 pre-conversion worker for Sonarr/Radarr/Jellyfin libraries. It watches mounted libraries for added/modified files, plans from `ffprobe` metadata, prefers lossless stream-copy, and validates output before publication or source removal.

Manage it at **Watchparty → profile actions → Media converter**, or `/converter` (administrator accounts). The webpage shows running jobs, progress, speed, policy, a reorderable queue, and history/errors. **Move to next** promotes any waiting file ahead of the queue immediately; up/down adjust individual positions. Active work finishes without losing progress. Pause stops new jobs; cancel interrupts a selected job. One Go binary still supplies the worker, CLI and TUI, sharing persistent SQLite state under `/data`.

The worker's HTTP API listens on internal port 8090. Watchparty authenticates administrators and proxies `/api/converter/*`; do not expose the worker directly. Both services use `MEDIA_CONVERTER_API_KEY`, falling back to their existing `SESSION_SECRET`. Production Compose already supplies the shared secrets and private network. For separate/local deployments, set `MEDIA_CONVERTER_URL` on Watchparty and matching service credentials.

## Safety Model

For `movie.mkv`, conversion writes `.movie.media-converter.tmp.mp4` in the same directory. The worker then:

1. Checks FFmpeg exited successfully.
2. Probes the temporary MP4 and requires a video stream.
3. Compares duration, resolution, and every planned audio/video/subtitle stream.
4. Optionally decodes the whole output when `DEEP_VALIDATION=true`.
5. Applies source mode, mtime, owner, and group where permissions allow.
6. Publishes `movie.mp4` with an atomic no-overwrite hard-link operation.
7. Deletes the original only when `DELETE_ORIGINAL=true`, no streams were omitted, and every prior step succeeded. Changed inputs or cancellation before publication discard temporary output.

Existing MP4 files are also inspected. Compatible files are skipped; incompatible ones are normalized with a validated atomic replacement. With `DELETE_ORIGINAL=false` (or omitted streams in non-strict mode), a hidden `.media-converter.original-*.mp4` backup retains the original before replacement. Hidden temporary/backup files are excluded from watching.

Failure and cancellation remove only the temporary output. The source is retained. If source cleanup itself fails, the valid MP4 remains and the job is marked failed for operator review.

Existing `movie.mkv` and `movie.mp4` pairs are marked `skipped` conflicts. Nothing is deleted. To resolve one explicitly, archive the existing MP4 and requeue the MKV:

```sh
docker exec media-converter media-converter resolve 42 archive-target
```

This renames the existing MP4 to a timestamped conflict backup; it does not delete it.

## Installation

```sh
cp docker-compose.example.yml docker-compose.yml
mkdir -p media-converter-data
docker compose up -d --build
docker logs -f media-converter
```

Mount the movie and TV roots read-write. The temporary and final output must be created beside each MKV for atomic publication. `/data` must be persistent.

The entrypoint maps the container account to `PUID`/`PGID` (default `1000:1000`) and drops root before starting the binary. Those IDs need read/write permission on the media and data mounts. On a typical host:

```sh
chown -R 1000:1000 ./media-converter-data
```

Do not recursively change a shared media library unless that ownership model is already correct for Sonarr, Radarr, and Jellyfin.

### Watch-Party Production Deploy

This repository's production Compose stack already includes `media-converter`. A push to `main` runs the existing GitHub Actions deploy, which invokes `deploy/up-prod.sh` and builds/recreates the converter alongside the rest of the stack. No additional GitHub secret, port, or media mount is required.

It automatically uses the existing `${MEDIA_ROOT}/media` Servarr import tree, mapping its movie and TV roots to `/media/movies` and `/media/tv`. State is persisted at `./data/media-converter`. The existing `SONARR_API_KEY`, `RADARR_API_KEY`, and optional `JELLYFIN_API_KEY` values from `secrets/.env.local` are used for post-replacement refresh hooks when present.

Optional production overrides go in `secrets/.env` or `secrets/.env.local`:

```env
MEDIA_CONVERTER_SCHEDULE=0 3 * * *
MEDIA_CONVERTER_MAX_CONCURRENT_JOBS=1
MEDIA_CONVERTER_DELETE_ORIGINAL=true
MEDIA_CONVERTER_MIN_FREE_SPACE_GB=20
```

Omit these overrides to use the shown defaults. After deploy, inspect it with `docker logs -f watchparty-media-converter` or open the TUI with `docker exec -it watchparty-media-converter media-converter tui`.

## Configuration

| Variable | Default | Purpose |
|---|---:|---|
| `MOVIES_DIR` | `/media/movies` | Movie scan root |
| `TV_DIR` | `/media/tv` | TV scan root |
| `DATA_DIR` | `/data` | SQLite and persistent state |
| `TZ` | `UTC` | IANA timezone used by cron |
| `SCHEDULE` | `0 3 * * *` | Five-field cron schedule |
| `MAX_CONCURRENT_JOBS` | `1` | FFmpeg worker count |
| `DEFAULT_PRIORITY` | `50` | Lower values run first |
| `DELETE_ORIGINAL` | `true` | Remove validated source MKV |
| `DRY_RUN` | `false` | Probe/plan globally without FFmpeg |
| `MIN_FREE_SPACE_GB` | `20` | Free space retained in addition to source size |
| `STRICT_MODE` | `true` | Fail instead of omitting unsupported streams |
| `WATCH_INTERVAL_SECONDS` | `15` | Automatic add/modify scan interval |
| `FILE_SETTLE_SECONDS` | `30` | Wait for stable file size/mtime before automatic queueing |
| `HTTP_ADDR` | `:8090` | Private HTTP control-plane listener |
| `MEDIA_CONVERTER_API_KEY` | `SESSION_SECRET` | Shared internal API credential |
| `DEEP_VALIDATION` | `false` | Decode full output after normal validation |
| `INCLUDE_SAMPLES` | `false` | Include `*.sample.mkv` files |
| `EXCLUDE_PATTERNS` | empty | Comma-separated filename/directory globs |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn`, or `error` |
| `LOG_FORMAT` | `pretty` | Set `json` for structured JSON stdout |
| `PUID`, `PGID` | `1000` | Runtime user and group IDs |

Built-in excluded directories are `@eaDir`, `.recycle`, `.Trash`, and `lost+found` (case-insensitive where applicable).

## Conversion Policy

The planner maps streams explicitly rather than using blind `-map 0`:

- Compatible H.264 8-bit 4:2:0 and HEVC 4:2:0 8/10-bit video are copied bit-for-bit; HEVC is tagged `hvc1` for Apple playback.
- Other SDR video is encoded as H.264 at original resolution, CRF 18, `veryfast`. This is high-quality **lossy** encoding, not lossless. Stream copying remains the fastest, lossless path. Unsupported HDR conversion is blocked pending an explicit tone-map policy rather than producing incorrect colors.
- AAC, AC-3, E-AC-3, ALAC, and MP3 audio are copied.
- FLAC and integer PCM up to 24-bit become ALAC without audio quality loss. Higher-precision lossless audio is blocked rather than silently truncated. Other audio becomes AAC at 256 kbit/s stereo or 512 kbit/s multichannel, preserving channel count.
- Existing `mov_text` subtitles are copied.
- SRT, ASS/SSA, WebVTT, and text subtitles are converted to `mov_text`.
- Bitmap/unsupported subtitles, attachments, fonts, and data streams block conversion by default. `STRICT_MODE=false` allows omissions but preserves the original file. ASS → `mov_text` does not retain exact ASS styling; a future sidecar-export policy is needed for exact styled/bitmap subtitle preservation.
- Stream language metadata and forced subtitle dispositions are retained where available.

## Scheduler And Recovery

The daemon polls filesystem metadata every 15 seconds, including files imported by rename and Docker bind mounts. It waits for stable size/mtime and a 30-second settle period. Unchanged files are deduplicated; modifications requeue eligible terminal/waiting jobs. Existing conflicting targets are not overwritten. A nightly scheduled reconciliation remains enabled in `TZ`. Jobs run by persisted priority and queue order, editable from the webpage while workers are active.

On startup, jobs interrupted in probing, conversion, or validation are returned to the queue and their known temporary files are removed. Docker `SIGTERM` stops new claims, sends FFmpeg `SIGTERM`, waits up to five seconds, and then forces termination if needed. The source is never touched during this path.

Low disk space blocks that job before FFmpeg starts and records a visible failure. Correct the space issue, then retry it.

## CLI

```sh
media-converter scan
media-converter scan --dry-run
media-converter convert --priority 10 "/media/movies/Dune Part Two (2024)"
media-converter convert --dry-run "/media/tv/Mr Robot"
media-converter status
media-converter queue
media-converter retry 42
media-converter cancel 42
media-converter priority 42 10
media-converter pause
media-converter resume
media-converter resolve 42 archive-target
```

`convert` recursively queues a file, movie directory, series, or season directory. Priority changes apply immediately to queued work but never preempt a running FFmpeg process. Cancellation is a persisted request observed by the daemon.

## TUI

```sh
docker exec -it media-converter media-converter tui
```

The active panel shows progress, FFmpeg speed, ETA, and source/output sizes. Library browsing is hierarchical: `Movies → movie → files` and `TV Shows → show → season → episodes`. Seasons and episodes use natural numeric ordering, so Season 2 appears before Season 10. Queue and History are separate views instead of one flat file list.

| Key | Action |
|---|---|
| `q` | Quit |
| `Enter` / right / `l` | Open the selected library level or job |
| left / `Esc` / `h` | Return to the previous level |
| `Tab` / `Shift+Tab` | Cycle Library, Queue, and History |
| `1`, `2`, `3` | Jump directly to Library, Queue, or History |
| arrows / `j`, `k` | Move the selection |
| `PgUp`, `PgDn` / `Ctrl+U`, `Ctrl+D` | Scroll by a page |
| `g`, `G` | Jump to the first or last item |
| `s` | Scan both libraries |
| `a` | Queue a file or directory path |
| `p` | Pause/resume new job claims |
| `Space` | Select or unselect a queued item for group reordering |
| `+` / `-` | Move the focused item or selected group up/down in the queue |
| `c` | Cancel selected job |
| `r` | Retry selected terminal job |
| `d` | Toggle dry-run for TUI-queued scans |
| `?` | Toggle the full key guide |

The layout automatically switches to a two-line list optimized for narrow phone terminals. Mouse-wheel events are also supported when the SSH client forwards terminal mouse input.

## Sonarr, Radarr, And Jellyfin

Filesystem operation is independent of all three APIs. When URLs and keys are configured, successful TV/movie replacements request a Sonarr/Radarr rescan. Jellyfin refreshes are debounced for two minutes so an episode batch produces one refresh rather than one request per file.

```env
SONARR_URL=http://sonarr:8989
SONARR_API_KEY=...
RADARR_URL=http://radarr:7878
RADARR_API_KEY=...
JELLYFIN_URL=http://jellyfin:8096
JELLYFIN_API_KEY=...
```

API failures are warnings and never affect the completed filesystem transaction.

## Development

```sh
make test
make build
make docker-build
```

Tests cover stream policy, FFmpeg argument generation, priority ordering and updates, path generation, duplicate insertion, duration tolerance, restart recovery, sample exclusion, and target conflict detection. FFmpeg integration requires real fixture media and is intentionally not part of the default unit suite.
