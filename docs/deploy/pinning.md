# Pinning: images, base images, and GitHub Actions

Everything external that a deploy pulls is pinned, so a given commit builds and runs the
same way tomorrow as it does today. Three kinds of pin, three procedures.

Do not hand-edit a digest. Resolve it, verify it, then paste it.

---

## 1. Service images in `docker-compose.prod.yml`

Pinned by **registry manifest digest** (`repo@sha256:…`) with the human-readable version in
a comment above. No tags — `:latest` and `:2-alpine` both move, which makes a deploy
irreproducible from its commit and lets `compose pull` swap a major version under a running
stack.

The digests committed on 2026-08-05 were not resolved from a registry. They were read from
the containers **actually running in production at that moment**, which is a stronger
guarantee than a registry lookup: it pins to a set already known to work together.

| Service | Version |
| --- | --- |
| caddy | v2.11.4 |
| jellyfin | 10.11.11 |
| livekit-server | v1.13.2 |
| coturn | 4.14.0-r0 |
| prowlarr | 2.4.0.5397-ls152 |
| sonarr | 4.0.19.2979-ls316 |
| radarr | 6.2.1.10461-ls308 |
| bazarr | v1.5.6-ls353 |
| qbittorrent | 5.2.2_v2.0.13-ls464 |

### To upgrade one service

On a host that can reach the registry:

```bash
# 1. See what the moving tag currently resolves to.
docker pull jellyfin/jellyfin:10.11.12
docker image inspect jellyfin/jellyfin:10.11.12 --format '{{index .RepoDigests 0}}'

# 2. Paste that digest into docker-compose.prod.yml and update the version comment.
# 3. Deploy it alone first, and confirm health before touching anything else.
docker compose --env-file secrets/.env -f docker-compose.prod.yml up -d jellyfin
./deploy/health-check.sh
```

### To re-derive the digest of something already running

```bash
docker inspect watchparty-jellyfin --format '{{.Config.Image}} {{.Image}}'
```

On a host using the containerd image store — which this deployment does — `.Image` and
`RepoDigests[0]` are the same manifest digest, so either is a valid pin. On the older
graph-driver store they differ: `.Image` is the *config* digest and pinning to it makes
every pull fail with a not-found. Always sanity-check that the value you are about to
commit also appears in `RepoDigests`:

```bash
docker image inspect <image> --format 'Id={{.Id}} RepoDigests={{.RepoDigests}}'
```

A manifest digest read from a single-arch local store is platform-specific (amd64 here). If
this stack is ever built for arm64, re-resolve against the multi-arch manifest list instead
of reusing these values.

---

## 2. The app's base image in `app/Dockerfile`

Pinned as an exact patch version through a build arg, not a digest:

```dockerfile
ARG NODE_VERSION=22.23.1
ARG NODE_IMAGE=node:${NODE_VERSION}-alpine
```

`22.23.1` is what `node:22-alpine` resolved to when the pin was set (Alpine 3.24.1, amd64,
manifest digest `sha256:16e22a55…`). A version tag rather than a digest is deliberate here:
the digest available locally is platform-specific, and hard-coding it would break a build
on an arm64 runner, whereas `node:22.23.1-alpine` resolves correctly on every architecture.
`.github/workflows/main.yml` pins `NODE_VERSION` to the same value so CI and the image agree.

### To upgrade

```bash
# Check what the current 22-alpine tag points at.
docker pull node:22-alpine
docker run --rm node:22-alpine node -v

# Update ARG NODE_VERSION in app/Dockerfile AND env.NODE_VERSION in
# .github/workflows/main.yml — they must match.
docker build --build-arg NODE_VERSION=<new> -t watchparty-app:test app/
```

To verify a build without network access to Docker Hub, override the whole reference with a
locally cached image:

```bash
docker build --build-arg NODE_IMAGE=node@sha256:<local-digest> -t watchparty-app:test app/
```

---

## 3. GitHub Actions in `.github/workflows/main.yml`

Every `uses:` is pinned to a **full 40-character commit SHA**, with the tag in a trailing
comment. A tag like `@v4` is a moving pointer the upstream owner can repoint at any commit,
which would change what code runs in this workflow with no corresponding change here.

```yaml
- uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4
```

### To upgrade or audit a pin

```bash
gh api repos/actions/checkout/git/ref/tags/v4 --jq '.object.sha'
```

Update the SHA and the trailing comment together — a comment that disagrees with its SHA is
worse than no comment. To audit every pin at once:

```bash
node -e "
const yaml=require('js-yaml'), fs=require('fs');
const w=yaml.load(fs.readFileSync('.github/workflows/main.yml','utf8'));
for (const [jn,j] of Object.entries(w.jobs)) for (const s of (j.steps||[]))
  if (s.uses && !/^[0-9a-f]{40}$/.test(s.uses.split('@')[1]))
    console.log('unpinned:', jn, s.uses);
"
```

Pins as of 2026-08-05, all verified against the live tags:

| Action | Tag | SHA |
| --- | --- | --- |
| actions/checkout | v4 | `11d5960a326750d5838078e36cf38b85af677262` |
| actions/setup-node | v4 | `49933ea5288caeca8642d1e84afbd3f7d6820020` |
| actions/upload-artifact | v4 | `ea165f8d65b6e75b540449e92b4886f43607fa02` |
| actions/download-artifact | v4 | `d3f86a106a0bac45b974a628896c90dbdf5c8093` |
| subosito/flutter-action | v2 | `1a449444c387b1966244ae4d4f8c696479add0b2` |
| appleboy/ssh-action | v1.2.0 | `7eaf76671a0d7eec5d98ee897acda4f968735a17` |
| appleboy/scp-action | v1 | `ff85246acaad7bdce478db94a363cd2bf7c90345` |
| gitleaks/gitleaks-action | v2 | `dcedce43c6f43de0b836d1fe38946645c9c638dc` |

`actions/checkout@v5` exists but was not adopted: this change pins what was already in use
rather than bundling a major-version upgrade into a security hardening pass.
