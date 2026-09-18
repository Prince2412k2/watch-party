# Media Converter

A persistent, Dockerized MKV-to-MP4 remux worker for Sonarr/Radarr/Jellyfin libraries. It scans mounted filesystems, plans conversions from `ffprobe` metadata, prefers stream-copy remuxing, and only removes an MKV after the MP4 has passed validation and been atomically published.

The service has no web UI or external database. One Go binary provides the daemon, CLI, cron scheduler, and Bubble Tea TUI; SQLite under `/data` is the control plane shared by `docker exec` commands.

## Safety Model

For `movie.mkv`, conversion writes `.movie.media-converter.tmp.mp4` in the same directory. The worker then:

1. Checks FFmpeg exited successfully.
2. Probes the temporary MP4 and requires a video stream.
3. Compares duration, resolution, and copied video codec with the MKV.
4. Optionally decodes the whole output when `DEEP_VALIDATION=true`.
5. Applies source mode, mtime, owner, and group where permissions allow.
6. Publishes `movie.mp4` with an atomic no-overwrite hard-link operation.
7. Deletes `movie.mkv` only when `DELETE_ORIGINAL=true` and every prior step succeeded.

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
| `STRICT_MODE` | `false` | Fail instead of omitting unsupported streams |
| `DEEP_VALIDATION` | `false` | Decode full output after normal validation |
| `INCLUDE_SAMPLES` | `false` | Include `*.sample.mkv` files |
| `EXCLUDE_PATTERNS` | empty | Comma-separated filename/directory globs |
| `LOG_LEVEL` | `info` | `debug`, `info`, `warn`, or `error` |
| `LOG_FORMAT` | `pretty` | Set `json` for structured JSON stdout |
| `PUID`, `PGID` | `1000` | Runtime user and group IDs |

Built-in excluded directories are `@eaDir`, `.recycle`, `.Trash`, and `lost+found` (case-insensitive where applicable).

## Conversion Policy

The planner maps streams explicitly rather than using blind `-map 0`:

- H.264, HEVC, AV1, and MPEG-4 video are copied.
- Other video codecs are marked `requires_transcode`; video transcoding is intentionally disabled.
- AAC, AC-3, E-AC-3, ALAC, and MP3 audio are copied.
- Other audio is converted to AAC while compatible tracks remain untouched.
- Existing `mov_text` subtitles are copied.
- SRT, ASS/SSA, WebVTT, and text subtitles are converted to `mov_text`.
- Bitmap/unsupported subtitles, attachments, fonts, and data streams are logged and omitted.
- `STRICT_MODE=true` turns any omission into a failure.
- Stream language metadata and forced subtitle dispositions are retained where available.

## Scheduler And Recovery

The daemon schedules scans internally in `TZ`; no host cron is needed. A scan does not add a duplicate row for a previously discovered source, and overlapping scheduled scans are skipped. Jobs run by priority and creation time.

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

The active panel shows operation type, progress, FFmpeg speed, ETA, and source/output sizes. The queue includes all pending, completed, failed, skipped, and `requires_transcode` jobs.

| Key | Action |
|---|---|
| `q` | Quit |
| `s` | Scan both libraries |
| `a` | Queue a file or directory path |
| `p` | Pause/resume new job claims |
| `+` / `-` | Raise/lower selected queued-job priority |
| `c` | Cancel selected job |
| `r` | Retry selected terminal job |
| `d` | Toggle dry-run for TUI-queued scans |
| arrows / `j`, `k` | Select a job |

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
