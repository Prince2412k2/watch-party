#!/usr/bin/env bash
# One-shot bring-up for the production stack (docker-compose.prod.yml).
#
# Exists because every piece of this has bitten us manually at least once:
#   - forgetting --env-file secrets/.env (VPS_PUBLIC_IP silently doesn't resolve)
#   - secrets/ files present but still containing placeholder values
#   - secrets/livekit.yaml hand-edited before a fix, then never re-synced
#     (secrets/ is gitignored — it NEVER moves via git pull/push)
#   - a container created before a secrets/ fix, needing --force-recreate
#     rather than a plain `up -d` to actually pick up the new value
#
# Usage (from the repo root, on the VPS):
#   ./deploy/up-prod.sh
#
# Safe to re-run — every step is idempotent. Never runs `down`, `-v`, or
# `--remove-orphans`; only ever brings things up.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

COMPOSE=(docker compose --env-file secrets/.env -f docker-compose.prod.yml)
FAIL=0

echo "== 1/4  Checking secrets/ =="
REQUIRED_FILES=(secrets/.env secrets/.env.local secrets/livekit.yaml secrets/coturn.conf secrets/Caddyfile)
for f in "${REQUIRED_FILES[@]}"; do
  if [ ! -f "$f" ]; then
    echo "  MISSING: $f  (see secrets/README.md)"
    FAIL=1
  fi
done
[ "$FAIL" = 1 ] && { echo "Aborting — fill in the missing secrets/ files first."; exit 1; }
echo "  all present"

echo ""
echo "== 2/4  Checking for leftover placeholder values =="
# Anything that still says YOUR_VPS_PUBLIC_IP / CHANGE_ME after setup is a
# guaranteed runtime failure (this is exactly the bug we chased earlier:
# livekit.yaml had a stale hardcoded node_ip that silently shadowed the env var).
if grep -rq 'YOUR_VPS_PUBLIC_IP\|CHANGE_ME' secrets/ 2>/dev/null; then
  echo "  Found unfilled placeholders:"
  grep -rn 'YOUR_VPS_PUBLIC_IP\|CHANGE_ME' secrets/ | sed 's/^/    /'
  echo "  Fix these in secrets/ before deploying — see secrets/README.md."
  exit 1
fi
echo "  clean"

echo ""
echo "== 3/4  Verifying VPS_PUBLIC_IP actually resolves through compose =="
RESOLVED_IP=$("${COMPOSE[@]}" config 2>/dev/null | grep -m1 'NODE_IP:' | awk '{print $2}')
if [ -z "$RESOLVED_IP" ] || [ "$RESOLVED_IP" = "YOUR_VPS_PUBLIC_IP" ]; then
  echo "  NODE_IP did not resolve to a real IP (got: '${RESOLVED_IP:-empty}')."
  echo "  Check VPS_PUBLIC_IP= in secrets/.env, and that no shell env var is"
  echo "  overriding it (echo \$VPS_PUBLIC_IP should be empty)."
  exit 1
fi
echo "  resolves to $RESOLVED_IP"

echo ""
echo "== 4/4  Bringing the stack up =="
"${COMPOSE[@]}" pull
# --force-recreate: cheap insurance against the exact class of bug above —
# a container created with a stale/placeholder value that a plain `up -d`
# would otherwise leave running untouched.
"${COMPOSE[@]}" up -d --build --force-recreate

echo ""
echo "== Waiting for healthchecked services =="
HEALTHCHECKED=(prowlarr sonarr radarr bazarr)
for i in $(seq 1 30); do
  ALL_HEALTHY=1
  for svc in "${HEALTHCHECKED[@]}"; do
    status=$(docker inspect --format '{{.State.Health.Status}}' "watchparty-${svc}" 2>/dev/null || echo "missing")
    [ "$status" != "healthy" ] && ALL_HEALTHY=0
  done
  [ "$ALL_HEALTHY" = 1 ] && break
  sleep 5
done

echo ""
echo "== Final status =="
docker compose -f docker-compose.prod.yml ps

echo ""
echo "Done. Next steps:"
echo "  - If this is a fresh setup, run deploy/connect-servarr.sh to wire"
echo "    Prowlarr/Sonarr/Radarr/Bazarr/qBittorrent together automatically."
echo "  - Check https://watch.sniffkin.tech/ loads and Caddy issued a cert:"
echo "      docker compose -f docker-compose.prod.yml logs caddy --tail 30"
