# Multi-stage production image for the watchparty app server.
#
# Three stages exist so the runtime image carries neither the client build
# toolchain (vite, typescript, and their transitive packages, none of which have
# any business in production) nor the server's devDependencies. Only production
# server deps, the server source, and the built client survive into the runtime
# stage.
#
# NODE_VERSION is an exact patch pin rather than a floating `node:22-alpine`:
# a floating tag changes underneath a deploy, which makes an image
# irreproducible from the commit that built it.
#
# 22.23.1 is not a guess — it is the version the `node:22-alpine` tag actually
# resolved to when this was written (Alpine 3.24.1, amd64, manifest digest
# sha256:16e22a55…). The digest is recorded in docs/deploy/pinning.md rather
# than inlined here, because a manifest digest from a containerd-backed local
# store is platform-specific and would break a build on an arm64 runner. See
# that doc for the procedure to verify this tag or promote it to a digest from a
# network-enabled host.
ARG NODE_VERSION=22.23.1
ARG NODE_IMAGE=node:${NODE_VERSION}-alpine

# ── Stage 1: production server dependencies only ──────────────────────────
# Built first because the client build depends on it — see the @humation/core
# note in stage 2.
#
# package-lock.json is required, not optional. The previous Dockerfile used a
# `package-lock.json*` glob plus `npm install`, which silently resolved fresh
# versions whenever the lock was absent — the opposite of a reproducible build.
# `npm ci` fails loudly instead.
FROM ${NODE_IMAGE} AS server-deps
WORKDIR /build

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# ── Stage 2: build the client (needs devDependencies — vite, tsc) ──────────
FROM ${NODE_IMAGE} AS client-build
WORKDIR /build/client

COPY client/package.json client/package-lock.json ./
RUN npm ci

COPY client/ ./

# app/shared/ is imported by BOTH trees — client/src/lib/avatar.ts reaches it as
# '../../../shared/avatar-derive.js' and server/avatar.js as
# '../shared/avatar-derive.js'. It must land at /build/shared so that relative
# path still resolves from /build/client/src/lib/.
COPY shared/ /build/shared/

# shared/avatar-derive.js imports @humation/core, which is declared in the
# SERVER's package.json, not the client's. The old single-stage Dockerfile only
# resolved this by accident: `COPY . .` plus a server `npm install` at /app left
# @humation/core in /app/node_modules, which Node then found by walking up from
# /app/shared/. Splitting the stages breaks that accident, so the server's
# production modules are staged at /build/node_modules — the parent of
# /build/shared — to restore the same resolution path deliberately.
COPY --from=server-deps /build/node_modules /build/node_modules

RUN npm run build

# ── Stage 3: runtime ──────────────────────────────────────────────────────
FROM ${NODE_IMAGE} AS runtime

# The node images ship a `node` user at uid/gid 1000. Reusing it rather than
# inventing a new uid matters because /data/sessions, /data/subtitles and
# /app/data are host bind mounts: the container uid must match the host
# directory owner or every session write fails at runtime. 1000 is already this
# deployment's convention (PUID=${PUID:-1000} across the Servarr services).
# deploy/up-prod.sh pre-flights host-side ownership and prints the required
# chown, because getting this wrong logs every user out on redeploy rather than
# failing visibly at startup.
ENV NODE_ENV=production \
    SERVE_CLIENT=1 \
    PORT=3000

WORKDIR /app

COPY --from=server-deps --chown=node:node /build/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node server/ ./server/
COPY --chown=node:node shared/ ./shared/
COPY --from=client-build --chown=node:node /build/client/dist ./client/dist

# Created in the image (not left to the bind mount) so it also runs without
# volumes — e.g. a CI smoke test.
RUN mkdir -p /data/sessions /data/subtitles /app/data \
 && chown -R node:node /data /app/data

USER node

EXPOSE 3000

# Uses Node's global fetch rather than curl/wget: the alpine base ships no curl,
# and this avoids installing a package solely to probe a local port.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/api/health').then(r=>{if(!r.ok)process.exit(1);return r.json()}).then(j=>process.exit(j&&j.ok?0:1)).catch(()=>process.exit(1))"

# `node server/index.js` rather than `npm start`: npm would sit between the init
# process and the server and swallow SIGTERM, degrading container stop into a
# 10-second SIGKILL timeout instead of a graceful shutdown.
CMD ["node", "server/index.js"]
