FROM node:22-alpine

# openssh-client: the Neko container-recreate reset (app/server/neko/container.js)
# shells out to `ssh neko-recreate@<host>` with a forced-command key mounted at
# runtime (NEKO_SSH_KEY_PATH) — never baked into this image. See
# docs/ops/neko-recreate.md.
RUN apk add --no-cache openssh-client

WORKDIR /app

# Server deps
COPY package.json package-lock.json* ./
RUN npm install

# Client deps
COPY client/package.json client/package-lock.json* ./client/
RUN cd client && npm install

# Source
COPY . .

# Build the client into client/dist so the Express server can serve it.
RUN cd client && npm run build

# Production serve: one port serves the built UI, /api, Socket.io, and the
# /jellyfin + /livekit reverse proxies. No source bind-mount at runtime — the
# image's built client/dist is authoritative (see docker-compose.yml).
ENV NODE_ENV=production
ENV SERVE_CLIENT=1
ENV PORT=3000

EXPOSE 3000

CMD ["npm", "start"]
