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

echo "== 1/6  Checking secrets/ =="
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
echo "== 2/6  Checking for leftover placeholder values =="
# Anything that still says YOUR_VPS_PUBLIC_IP / CHANGE_ME after setup is a
# guaranteed runtime failure (this is exactly the bug we chased earlier:
# livekit.yaml had a stale hardcoded node_ip that silently shadowed the env var).
#
# Scoped to the files the stack actually READS, not `-r secrets/`. The recursive
# form scanned everything in the directory — including secrets/README.md, whose
# job is to document the placeholders, and any .bak a human left behind while
# fixing one. Both block the deploy with a message pointing at a file nobody is
# editing, which is exactly what happened: a backup taken thirty seconds
# earlier aborted the bring-up and read like the fix had not worked.
#
# A commented-out line is not a live setting either, so those are skipped —
# an example left in a comment is documentation, not misconfiguration.
PLACEHOLDER_HITS=""
for f in "${REQUIRED_FILES[@]}"; do
  # Anchored at the line number, so a value that merely CONTAINS ":#" is not
  # mistaken for a comment and silently skipped. A false negative here is worse
  # than a false positive: it is the placeholder shipping to production.
  hits="$(grep -nE 'YOUR_VPS_PUBLIC_IP|CHANGE_ME' "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*[#;]' || true)"
  [ -n "$hits" ] && PLACEHOLDER_HITS="${PLACEHOLDER_HITS}${f}:${hits}"$'\n'
done
if [ -n "$PLACEHOLDER_HITS" ]; then
  echo "  Found unfilled placeholders in live settings:"
  printf '%s' "$PLACEHOLDER_HITS" | sed 's/^/    /'
  echo "  Fix these in secrets/ before deploying — see secrets/README.md."
  exit 1
fi
echo "  clean"

echo ""
echo "== 3/6  Verifying VPS_PUBLIC_IP actually resolves through compose =="
RESOLVED_IP=$("${COMPOSE[@]}" config 2>/dev/null | grep -m1 'NODE_IP:' | awk '{print $2}')
if [ -z "$RESOLVED_IP" ] || [ "$RESOLVED_IP" = "YOUR_VPS_PUBLIC_IP" ]; then
  echo "  NODE_IP did not resolve to a real IP (got: '${RESOLVED_IP:-empty}')."
  echo "  Check VPS_PUBLIC_IP= in secrets/.env, and that no shell env var is"
  echo "  overriding it (echo \$VPS_PUBLIC_IP should be empty)."
  exit 1
fi
echo "  resolves to $RESOLVED_IP"

# coturn does NOT read the environment — it reads secrets/coturn.conf, which
# compose bind-mounts verbatim. So the check above proves nothing about it, and
# for a long time nothing else did either: external-ip sat at the literal
# YOUR_VPS_PUBLIC_IP in production.
#
# That is the address TURN advertises as its relay candidate. Wrong, it is not
# an error anyone sees — STUN still works, so most people connect fine and only
# users behind symmetric NAT or a restrictive firewall silently fail to get
# video. "Works for everyone except a few" is the worst shape a fault can take,
# and it is why this is asserted rather than trusted.
COTURN_IP="$(grep -m1 '^external-ip=' secrets/coturn.conf 2>/dev/null | cut -d= -f2- | xargs || true)"
if [ -z "$COTURN_IP" ]; then
  echo "  coturn.conf has no live external-ip= line."
  echo "  TURN relay will advertise nothing. Set it to $RESOLVED_IP."
  exit 1
fi
if [ "$COTURN_IP" != "$RESOLVED_IP" ]; then
  echo "  coturn external-ip does not match VPS_PUBLIC_IP."
  echo "  compose resolves $RESOLVED_IP; secrets/coturn.conf advertises $COTURN_IP."
  echo "  TURN relay candidates would point somewhere the client cannot reach."
  exit 1
fi
echo "  coturn external-ip agrees"

echo ""
echo "== 4/6  Verifying the admin-port firewall =="
# docker-compose.prod.yml publishes the admin UIs on 0.0.0.0, so these rules are
# the only thing keeping Jellyfin/Sonarr/Radarr/Bazarr/Prowlarr/qBittorrent and
# the app's own port off the public internet. Bringing the stack up without them
# would publish every admin UI, so this is a hard gate rather than a warning.
if ! sudo -n ./deploy/firewall.sh --verify >/tmp/wp-fw-verify.$$ 2>&1; then
  if grep -q 'must run as root' /tmp/wp-fw-verify.$$; then
    echo "  Cannot verify without root. Run:  sudo ./deploy/firewall.sh --verify"
    echo "  Aborting — refusing to expose admin ports unverified."
  else
    sed 's/^/  /' /tmp/wp-fw-verify.$$
    echo ""
    echo "  Admin ports are NOT protected. Apply the rules first:"
    echo "      sudo ./deploy/firewall.sh"
  fi
  rm -f /tmp/wp-fw-verify.$$
  exit 1
fi
sed 's/^/  /' /tmp/wp-fw-verify.$$
rm -f /tmp/wp-fw-verify.$$

echo ""
echo "== 5/6  Checking bind-mount ownership for the non-root app container =="
# app/Dockerfile runs the server as uid 1000 (the image's `node` user). The
# session store, subtitle cache and data dir are host bind mounts, so if the host
# directories are owned by root the container cannot write them — and the visible
# symptom is every user being logged out on redeploy, not a startup error. Fail
# here with the fix instead.
APP_UID=1000
OWNERSHIP_FAIL=0
for d in data data/sessions data/subtitles; do
  [ -d "$d" ] || mkdir -p "$d"
  owner="$(stat -c %u "$d")"
  if [ "$owner" != "$APP_UID" ]; then
    echo "  WRONG OWNER: $d is uid $owner, needs $APP_UID"
    OWNERSHIP_FAIL=1
  fi
done
if [ "$OWNERSHIP_FAIL" = 1 ]; then
  echo ""
  echo "  Fix with:  sudo chown -R $APP_UID:$APP_UID data"
  echo "  Aborting — the app would start but fail to persist sessions."
  exit 1
fi
echo "  data dirs owned by uid $APP_UID"

echo ""
echo "== 6/6  Bringing the stack up =="
"${COMPOSE[@]}" pull
# --force-recreate: cheap insurance against the exact class of bug above —
# a container created with a stale/placeholder value that a plain `up -d`
# would otherwise leave running untouched.
"${COMPOSE[@]}" up -d --build --force-recreate

echo ""
echo "== Waiting for health =="
# This used to be an inline wait loop over the four Servarr containers that
# discarded its own result: if they never became healthy the loop simply expired
# and the script carried on to print "Done.", exiting 0 over a broken stack.
# deploy/health-check.sh owns the probing now and its exit status is respected,
# so an unhealthy deploy fails loudly.
echo ""
echo "== Final status =="
docker compose -f docker-compose.prod.yml ps

echo ""
if ! ./deploy/health-check.sh; then
  echo ""
  echo "Stack is up but NOT healthy — see the failures and rollback command above." >&2
  exit 1
fi

echo ""
echo "Done. Next steps:"
echo "  - If this is a fresh setup, run deploy/connect-servarr.sh to wire"
echo "    Prowlarr/Sonarr/Radarr/Bazarr/qBittorrent together automatically."
echo "  - Check https://watch.example.com/ loads and Caddy issued a cert:"
echo "      docker compose -f docker-compose.prod.yml logs caddy --tail 30"
