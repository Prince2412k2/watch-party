#!/usr/bin/env bash
# Post-deploy health gate for the production stack.
#
# Exits NONZERO if any critical service is not healthy within the timeout, so CI
# and deploy scripts fail loudly instead of reporting a green deploy over a
# broken stack. On failure it prints the exact rollback command, including the
# commit to roll back to, because the recovery path here is deliberately manual
# (see docs/deploy/rollback.md) and a runbook you have to reconstruct under
# pressure is not a runbook.
#
# Usage:
#   ./deploy/health-check.sh                 # wait up to TIMEOUT for health
#   TIMEOUT=180 ./deploy/health-check.sh
#   HEALTH_PUBLIC_URL=https://watch.example.com/api/health ./deploy/health-check.sh
#
# Exit codes:  0 = all critical services healthy
#              1 = a critical service is unhealthy, missing, or timed out

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TIMEOUT="${TIMEOUT:-150}"
INTERVAL="${INTERVAL:-5}"

# Critical = on the watch path. If any of these is unhealthy, nobody can watch
# anything, so a deploy must not be considered successful.
CRITICAL=(watchparty-app watchparty-jellyfin watchparty-livekit watchparty-caddy)

# Reported but NOT deploy-blocking: these serve the library/download flow, not
# playback. A failing Sonarr should not roll back a working watch party.
ADVISORY=(watchparty-prowlarr watchparty-sonarr watchparty-radarr watchparty-bazarr)

log()  { printf '%s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; }

# Health status of a container, normalised. Containers with no healthcheck
# report "none"; treat a running-but-unprobed container as "running" rather than
# silently passing it as healthy.
status_of() {
  local name="$1" state health
  state="$(docker inspect --format '{{.State.Status}}' "$name" 2>/dev/null)" || { printf 'missing'; return; }
  [ -z "$state" ] && { printf 'missing'; return; }
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null)"
  if [ "$state" != "running" ]; then printf '%s' "$state"; return; fi
  case "$health" in
    healthy)   printf 'healthy' ;;
    none)      printf 'running-no-healthcheck' ;;
    *)         printf '%s' "$health" ;;
  esac
}

# ── Wait for the critical set ──────────────────────────────────────────────
deadline=$(( SECONDS + TIMEOUT ))
declare -A final=()
all_ok=0

while :; do
  all_ok=1
  for c in "${CRITICAL[@]}"; do
    s="$(status_of "$c")"
    final["$c"]="$s"
    [ "$s" = "healthy" ] || all_ok=0
  done
  [ "$all_ok" = 1 ] && break
  [ "$SECONDS" -ge "$deadline" ] && break
  sleep "$INTERVAL"
done

log "== Critical services (timeout ${TIMEOUT}s) =="
for c in "${CRITICAL[@]}"; do
  printf '  %-24s %s\n' "$c" "${final[$c]}"
done

log ""
log "== Advisory services (not deploy-blocking) =="
for c in "${ADVISORY[@]}"; do
  printf '  %-24s %s\n' "$c" "$(status_of "$c")"
done

# ── Optional end-to-end probe through Caddy ────────────────────────────────
# Container health only proves the app answers on localhost. This proves TLS,
# Caddy routing and the public path actually work — the thing users hit.
public_ok=1
if [ -n "${HEALTH_PUBLIC_URL:-}" ]; then
  log ""
  log "== Public endpoint =="
  code="$(curl -sS -o /dev/null -w '%{http_code}' -m 15 "$HEALTH_PUBLIC_URL" 2>/dev/null || echo 000)"
  printf '  %-24s HTTP %s\n' "$HEALTH_PUBLIC_URL" "$code"
  [ "$code" = "200" ] || public_ok=0
fi

if [ "$all_ok" = 1 ] && [ "$public_ok" = 1 ]; then
  log ""
  log "All critical services healthy."
  exit 0
fi

# ── Failure path: say what broke, and exactly how to undo it ───────────────
log ""
for c in "${CRITICAL[@]}"; do
  [ "${final[$c]}" = "healthy" ] || fail "$c is ${final[$c]}"
done
[ "$public_ok" = 1 ] || fail "public endpoint ${HEALTH_PUBLIC_URL:-} did not return 200"

# ORIG_HEAD is what `git pull` leaves pointing at the pre-pull commit, so it is
# the right rollback target after a deploy. HEAD@{1} covers a reset-based
# deploy; if neither resolves we say so rather than printing a wrong SHA.
prev="$(git rev-parse --verify --quiet ORIG_HEAD || git rev-parse --verify --quiet 'HEAD@{1}' || true)"
cur="$(git rev-parse --short HEAD 2>/dev/null || echo '<unknown>')"

# If the candidate resolves to the commit already checked out, rolling back to it
# would be a no-op — which is worse than saying nothing, because it looks like a
# valid recovery step. Happens when no pull preceded this run (fresh clone or
# worktree, or a re-run of health-check without a redeploy).
if [ -n "$prev" ] && [ "$prev" = "$(git rev-parse HEAD 2>/dev/null)" ]; then
  prev=""
fi

cat >&2 <<EOF

────────────────────────────────────────────────────────────────────────
DEPLOY UNHEALTHY — production is still running commit $cur
Rollback is manual by design. See docs/deploy/rollback.md.
EOF

if [ -n "$prev" ]; then
  cat >&2 <<EOF

  cd /opt/watch-party
  git reset --hard ${prev}
  docker compose --env-file secrets/.env -f docker-compose.prod.yml up -d --build
  ./deploy/health-check.sh
EOF
else
  cat >&2 <<'EOF'

  Could not determine the previous commit (no ORIG_HEAD or HEAD@{1}).
  Pick the last known-good SHA from `git log --oneline` and run:

  cd /opt/watch-party
  git reset --hard <known-good-sha>
  docker compose --env-file secrets/.env -f docker-compose.prod.yml up -d --build
  ./deploy/health-check.sh
EOF
fi

printf '────────────────────────────────────────────────────────────────────────\n' >&2
exit 1
