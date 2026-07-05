# Media-acquisition stack — bring-up guide (Phase 5.0)

This deploys the automation stack that finds, downloads, and organizes media
into a library Jellyfin serves:

| Service      | Role                         | Image                                |
|--------------|------------------------------|--------------------------------------|
| Prowlarr     | Indexer manager (search)     | `lscr.io/linuxserver/prowlarr`       |
| Sonarr       | TV shows                     | `lscr.io/linuxserver/sonarr`         |
| Radarr       | Movies                       | `lscr.io/linuxserver/radarr`         |
| Bazarr       | Subtitles                    | `lscr.io/linuxserver/bazarr`         |
| qBittorrent  | Torrent download client      | `lscr.io/linuxserver/qbittorrent`    |

Files:
- `docker-compose.servarr.yml` (repo root) — the stack
- `.env.servarr.example` (repo root) — config template -> copy to `.env.servarr`
- this guide

Nothing is running yet. Follow the steps below to bring it up yourself.

---

## Prerequisites

- Docker + Docker Compose v2 on the host.
- Your host UID/GID (`id -u`, `id -g`) for `PUID`/`PGID`.
- Enough disk on the volume that will hold `MEDIA_ROOT`.
- **Torrenting carries legal/ISP risk. Use a VPN or a seedbox as your
  policies require. This guide does not configure a VPN.**

---

## 1. Configure

```bash
cd <repo root>
cp .env.servarr.example .env.servarr
$EDITOR .env.servarr        # set PUID, PGID, TZ, MEDIA_ROOT, CONFIG_ROOT
```

Create the directory layout under `MEDIA_ROOT` (single tree — see
"Why one /data mount" below):

```bash
# using the default MEDIA_ROOT=./media-data
mkdir -p media-data/downloads media-data/media/movies media-data/media/tv
```

## 2. Bring up

```bash
docker compose -f docker-compose.servarr.yml --env-file .env.servarr up -d
docker compose -f docker-compose.servarr.yml ps
```

Open the UIs (default ports):

- Prowlarr    http://localhost:9696
- Sonarr      http://localhost:8989
- Radarr      http://localhost:7878
- Bazarr      http://localhost:6767
- qBittorrent http://localhost:8080

---

## Automated wiring (recommended)

Instead of clicking through the manual "First-run setup order" below, run the
idempotent wiring script. It cross-connects the whole stack via each service's
REST API:

```bash
docker compose -f docker-compose.servarr.yml --env-file .env.servarr up -d
./deploy/connect-servarr.sh
```

What it does (each step is existence-checked, so re-running is a safe no-op):

1. Adds **qBittorrent** as a download client to **Radarr** and **Sonarr**
   (host `qbittorrent:8080`, categories `radarr` / `tv-sonarr`).
2. Ensures the root folders `/data/media/movies` (Radarr) and `/data/media/tv`
   (Sonarr).
3. Registers **Radarr + Sonarr** in **Prowlarr** as `fullSync` applications
   (Prowlarr self-URL `http://prowlarr:9696`), so indexers auto-propagate.
4. Confirms the **qBittorrent** WebUI login matches `.env.local` and sets the
   default save path to `/data/downloads`.
5. Connects **Bazarr** to Radarr + Sonarr for subtitles.

Properties:

- **Idempotent.** Every create is preceded by a GET-and-match check; existing
  user config is never duplicated or overwritten. Prints a per-step status of
  `[created]`, `[exists, skipped]`, or `[warn]`.
- **No secrets in the script/output.** API keys are read at runtime from
  `servarr-config/<app>/config.xml` (Bazarr: `.../bazarr/config/config.yaml`)
  and qBittorrent creds from `.env.local`. Nothing secret is hardcoded, echoed,
  or logged.
- **Waits for readiness.** Polls each service (`/ping` / health) before
  configuring it, so it can be run immediately after `up -d`.
- Requires `curl` and `jq` on the host.

**The only remaining manual step:** add your indexers in Prowlarr
(**Settings -> Indexers -> Add Indexer**). Because Radarr and Sonarr are
registered as `fullSync` apps, each indexer you add auto-syncs to both — no
per-app indexer setup. (On a brand-new Prowlarr you must also pick an auth
method on first load.)

The manual "First-run setup order" below remains as reference and as a fallback
if the API is ever unreachable.

---

## Port map

| Service      | Host port (env)          | Container | Notes                          |
|--------------|--------------------------|-----------|--------------------------------|
| Prowlarr     | `PROWLARR_PORT` 9696     | 9696      |                                |
| Sonarr       | `SONARR_PORT` 8989       | 8989      |                                |
| Radarr       | `RADARR_PORT` 7878       | 7878      |                                |
| Bazarr       | `BAZARR_PORT` 6767       | 6767      |                                |
| qBittorrent  | `QBITTORRENT_PORT` 8080  | 8080      | WebUI                          |
| qBittorrent  | `QBITTORRENT_BT_PORT` 6881 | 6881    | BitTorrent TCP+UDP (peers)     |

Deliberately clear of the app (3000 published / 3001 in-container),
Jellyfin (8096), and LiveKit (7880-7882) from the root `docker-compose.yml`.

---

## Why one `/data` mount (hardlinks / atomic moves)

Every media-touching container (qBittorrent, Sonarr, Radarr, Bazarr) mounts a
single host tree `MEDIA_ROOT` at `/data`. Downloads and the final library are
therefore on the **same filesystem**, which lets Sonarr/Radarr **hardlink**
(or instant atomic-move) a finished download into the library:

- no second copy — the file exists once on disk, in two places;
- the import is instant even for large files;
- qBittorrent keeps seeding from the original path (same inode).

If downloads and library were separate mounts (the classic mistake — mapping
`/downloads` and `/movies` as two volumes), every import becomes a slow
copy that doubles disk usage and can break seeding. This is the
[TRaSH-guides](https://trash-guides.info/) recommended layout.

Layout inside the containers (all under the single `/data`):

```
/data
├── downloads          <- qBittorrent default save path
└── media
    ├── movies         <- Radarr root folder
    └── tv             <- Sonarr root folder
```

---

## First-run setup order

Do this in order; later steps depend on earlier ones.

### A. qBittorrent — secure it first
1. Get the temporary admin password: `docker logs watchparty-qbittorrent`
   (recent LSIO images print a randomized password on first boot).
2. Log in at http://localhost:8080 (user `admin`).
3. **Settings -> Web UI**: set a strong username/password. These are the
   `QBITTORRENT_USER` / `QBITTORRENT_PASS` the app uses later.
4. **Settings -> Downloads**: set the default save path to `/data/downloads`.

### B. Prowlarr — indexers
1. http://localhost:9696 -> set an auth method (Forms login) on first run.
2. **Indexers -> Add Indexer**: add the trackers/indexers you use.
3. **Settings -> Apps -> Add**: add Sonarr and Radarr so Prowlarr pushes its
   indexers to them automatically.
   - Prowlarr Server: `http://prowlarr:9696`
   - Sonarr:  `http://sonarr:8989`  + Sonarr's API key
   - Radarr:  `http://radarr:7878`  + Radarr's API key
   (These `http://<name>:<port>` URLs work because all services share the
   `servarr` network. If Prowlarr can't reach them, see the network note.)

### C. Sonarr (TV) and Radarr (Movies)
For each:
1. **Settings -> Download Clients -> Add -> qBittorrent**
   - Host: `qbittorrent`  Port: `8080`
   - Username/Password: what you set in step A.3.
2. **Settings -> Media Management -> Root Folders -> Add**
   - Sonarr: `/data/media/tv`
   - Radarr: `/data/media/movies`
3. Confirm hardlinking: **Settings -> Media Management** -> "Use Hardlinks
   instead of Copy" enabled (default).

### D. Bazarr — subtitles
1. http://localhost:6767
2. **Settings -> Sonarr**: Address `sonarr`, Port `8989`, Sonarr API key.
3. **Settings -> Radarr**: Address `radarr`, Port `7878`, Radarr API key.
4. **Settings -> Languages**: add providers and the languages you want.
   Bazarr sees the media via the shared `/data` mount and writes `.srt`
   sidecars next to each video.

---

## Where each API key comes from

| Value                 | Where                                                                 |
|-----------------------|-----------------------------------------------------------------------|
| `PROWLARR_API_KEY`    | Prowlarr -> Settings -> General -> Security -> API Key                 |
| `SONARR_API_KEY`      | Sonarr  -> Settings -> General -> Security -> API Key                  |
| `RADARR_API_KEY`      | Radarr  -> Settings -> General -> Security -> API Key                  |
| `BAZARR_API_KEY`      | Bazarr  -> Settings -> General -> Security -> API Key                  |
| `QBITTORRENT_USER/PASS` | qBittorrent -> Settings -> Web UI (no API key; WebUI creds)          |

Each key is generated by the service on first run. Copy each once it exists.

---

## How these feed the app (`.env.local`) for Phase 5.1+

The app loads `.env` then `.env.local` (see `app/server/index.js`);
`.env.local` is gitignored and is where **you** keep real secrets. Do NOT put
real keys in `.env.servarr` or `.env` — those are committed/templates.

After first-run setup, add to `.env.local`:

```
# Media-acquisition integration (Phase 5.1+)
PROWLARR_URL=http://prowlarr:9696
PROWLARR_API_KEY=<from Prowlarr UI>
SONARR_URL=http://sonarr:8989
SONARR_API_KEY=<from Sonarr UI>
RADARR_URL=http://radarr:7878
RADARR_API_KEY=<from Radarr UI>
BAZARR_URL=http://bazarr:6767
BAZARR_API_KEY=<from Bazarr UI>
QBITTORRENT_URL=http://qbittorrent:8080
QBITTORRENT_USER=<your qbt user>
QBITTORRENT_PASS=<your qbt pass>
```

Use `http://<container-name>:<port>` URLs **only if the app shares the servarr
network** (see next section). If the app runs on the host, use
`http://localhost:<port>` (or the host's LAN/tailnet address) instead — this
matches the pattern already used for `JELLYFIN_URL` (`http://jellyfin:8096`
in-compose vs `http://localhost:8096` fallback in `app/server/jellyfin.js`).

---

## Integrating with the app / Jellyfin compose

The root `docker-compose.yml` already runs `jellyfin`, `livekit`, and
`watchparty` on the default compose network. This stack is **additive** and
intentionally does not modify it. Two integration options:

### Option 1 — run alongside (simplest)
Keep them on separate networks. The app reaches the servarr services via the
host: `http://localhost:9696`, `:8989`, etc. Works today, no edits needed.

### Option 2 — shared external network (name-based addressing)
Let the app/Jellyfin address the servarr services by container name.

```bash
docker network create watchparty-net
```

Then in **both** compose files add the app + servarr services to it. In
`docker-compose.servarr.yml`, change the `networks:` block to:

```yaml
networks:
  servarr:
    name: watchparty-net
    external: true
```

and in the root `docker-compose.yml` add to the `watchparty` (and, if you
want name-based library scans, `jellyfin`) service:

```yaml
    networks:
      - default
      - watchparty-net
networks:
  watchparty-net:
    external: true
```

This is additive — it does not change existing volumes or ports.

### Wiring Jellyfin to the same media tree
Jellyfin currently mounts `./media:/media` in the root compose. For Jellyfin
to serve what Sonarr/Radarr import, point its library at the **same host tree**
as `MEDIA_ROOT`. Either:
- set `MEDIA_ROOT=./media` in `.env.servarr` so both use `./media`, and add
  Jellyfin libraries pointing at `/media/media/movies` and `/media/media/tv`;
  **or**
- add a second Jellyfin mount, e.g. `- ${MEDIA_ROOT}/media:/library`, and add
  Jellyfin libraries `/library/movies` and `/library/tv`.

The key invariant: the files Radarr/Sonarr write must appear inside a path
Jellyfin has mounted. (Editing the root compose's Jellyfin mount is optional
and left to you — this task did not modify it.)

---

## Security notes

- **Do not expose these UIs publicly.** They have weak/optional auth and are
  attack surface. Keep them on the LAN or behind your tailnet
  (a `*.ts.net` origin is already trusted by the app's CORS config). Do not
  publish 9696/8989/7878/6767/8080 through a public reverse proxy without
  auth in front.
- **Change qBittorrent's default credentials immediately** (step A). The
  temporary password is only for first login.
- **Torrent listen port (6881):** forwarding it improves peer connectivity
  but also advertises your node — only forward if you understand the exposure,
  ideally behind a VPN.
- **API keys are secrets.** They grant full control of each service. Keep them
  in `.env.local` (gitignored) — never in `.env`, `.env.servarr`, or commits.
- **Legal:** you are responsible for what you download/seed. Configure a VPN
  or seedbox per your requirements before adding indexers.

---

## Teardown

```bash
docker compose -f docker-compose.servarr.yml --env-file .env.servarr down
# add -v to also remove named volumes (there are none here; config lives on
# the host under CONFIG_ROOT, so `down` keeps your settings).
```
