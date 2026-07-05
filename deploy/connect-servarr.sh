#!/usr/bin/env bash
#
# connect-servarr.sh — idempotently auto-wire the watch_party Servarr stack.
#
# What it does (each step is GET-and-match guarded, so it is safe to re-run):
#   1. Adds qBittorrent as a download client to Radarr and Sonarr.
#   2. Ensures the Radarr (/data/media/movies) and Sonarr (/data/media/tv) root folders.
#   3. Registers Radarr + Sonarr in Prowlarr as fullSync applications.
#   4. Confirms qBittorrent WebUI credentials and sets the default save path to /data/downloads.
#   5. Connects Bazarr to Radarr + Sonarr for subtitles.
#
# It deliberately does NOT add indexers — that is the one manual step (see the
# closing message). Run it from anywhere:  ./deploy/connect-servarr.sh
#
# SECRETS: every API key / password is read at runtime from the bind-mounted
# config files (servarr-config/<app>/config.xml, .../bazarr/config/config.yaml)
# and .env.local. Nothing secret is ever printed, logged, or hardcoded here.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Paths — anchor everything to the repo root (this file lives in deploy/).
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Host-facing base URLs (script runs on the HOST; override via env if needed).
# NOTE: the URLs the apps use to reach EACH OTHER are container-internal and
# are hardcoded in the payloads below (qbittorrent:8080, radarr:7878,
# sonarr:8989, prowlarr:9696) — those are correct on this stack.
# ---------------------------------------------------------------------------
RADARR_URL="${RADARR_URL:-http://localhost:7878}"
SONARR_URL="${SONARR_URL:-http://localhost:8989}"
PROWLARR_URL="${PROWLARR_URL:-http://localhost:9696}"
BAZARR_URL="${BAZARR_URL:-http://localhost:6767}"
QBIT_URL="${QBITTORRENT_URL_HOST:-http://localhost:8080}"

# Readiness polling knobs.
WAIT_RETRIES="${WAIT_RETRIES:-30}"   # attempts per service
WAIT_SLEEP="${WAIT_SLEEP:-2}"        # seconds between attempts

# ---------------------------------------------------------------------------
# Pretty output helpers.
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_OK=$'\e[32m'; C_SKIP=$'\e[33m'; C_WARN=$'\e[31m'; C_HD=$'\e[1;36m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
  C_OK=; C_SKIP=; C_WARN=; C_HD=; C_DIM=; C_RST=
fi

SUMMARY=()
header()  { printf '\n%s== %s ==%s\n' "$C_HD" "$*" "$C_RST"; }
info()    { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RST"; }
status()  {
  # status <tag> <message...>   tag ∈ created | exists, skipped | warn
  local tag="$1"; shift; local color
  case "$tag" in
    created)          color=$C_OK ;;
    updated)          color=$C_OK ;;
    "exists, skipped") color=$C_SKIP ;;
    warn)             color=$C_WARN ;;
    *)                color=$C_RST ;;
  esac
  printf '  %s[%s]%s %s\n' "$color" "$tag" "$C_RST" "$*"
  SUMMARY+=("[$tag] $*")
}

# ---------------------------------------------------------------------------
# HTTP helper. Writes the response body into the global RESP and the HTTP code
# into HTTP_STATUS. It is called DIRECTLY (never inside $()) so those globals
# survive in the caller's shell — a command-substitution subshell would drop
# them. curl -s means 4xx/5xx still return 0 (code lives in HTTP_STATUS); only a
# real network failure yields HTTP_STATUS=000. Secrets are passed via -H/--data
# and are never echoed.
# ---------------------------------------------------------------------------
RESP=""; HTTP_STATUS=""
_curl() {
  local out
  if out="$(curl -s -w $'\n%{http_code}' --max-time 30 "$@" 2>/dev/null)"; then
    HTTP_STATUS="${out##*$'\n'}"
    RESP="${out%$'\n'*}"
  else
    HTTP_STATUS="000"; RESP=""
  fi
  return 0
}

# Lightweight code-only probe used by the readiness poller.
_http_code() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$@" 2>/dev/null || printf '000'
}

# wait_for <label> <url> [ready-code-regex]  — poll until reachable.
wait_for() {
  local label="$1" url="$2" ready="${3:-200}" i code=000
  printf '  waiting for %-11s ' "$label"
  for ((i=1; i<=WAIT_RETRIES; i++)); do
    code="$(_http_code "$url")"
    if [[ "$code" =~ ^(${ready})$ ]]; then
      printf '%sok%s (HTTP %s)\n' "$C_OK" "$C_RST" "$code"
      return 0
    fi
    printf '.'
    sleep "$WAIT_SLEEP"
  done
  printf ' %stimeout%s (last HTTP %s)\n' "$C_WARN" "$C_RST" "$code"
  return 1
}

# jq wrapper over the last RESP; returns jq's own exit code (for -e tests).
resp_has() { printf '%s' "$RESP" | jq -e "$@" >/dev/null 2>&1; }
resp_get() { printf '%s' "$RESP" | jq -r "$@" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# Secret extraction — assign to shell vars only; never echo the values.
# ---------------------------------------------------------------------------
read_arr_key() {
  # $1 = app dir name under servarr-config/ (radarr|sonarr|prowlarr)
  local f="$REPO_ROOT/servarr-config/$1/config.xml"
  [ -f "$f" ] && grep -oPm1 '(?<=<ApiKey>)[^<]+' "$f" || true
}

read_bazarr_key() {
  local f="$REPO_ROOT/servarr-config/bazarr/config/config.yaml"
  [ -f "$f" ] || return 0
  if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 -c "import yaml;print(yaml.safe_load(open('$f'))['auth']['apikey'])" 2>/dev/null || true
  else
    # pure-shell fallback: read auth.apikey without PyYAML
    awk '/^auth:/{a=1;next} /^[a-z_]+:/{a=0} a&&/apikey:/{print $2;exit}' "$f"
  fi
}

# Read a single value from .env.local WITHOUT sourcing it (values may contain
# characters that would break shell sourcing). First match wins; quotes stripped.
read_env_local() {
  local f="$REPO_ROOT/.env.local" line
  [ -f "$f" ] || return 0
  line="$(grep -E "^$1=" "$f" | head -n1 || true)"
  line="${line#*=}"
  line="${line%\"}"; line="${line#\"}"
  line="${line%\'}"; line="${line#\'}"
  printf '%s' "$line"
}

# ---------------------------------------------------------------------------
# Dependency check.
# ---------------------------------------------------------------------------
for bin in curl jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "ERROR: '$bin' is required but not installed." >&2; exit 1; }
done

header "Reading credentials (from bind-mounted config; nothing printed)"
RADARR_KEY="$(read_arr_key radarr)"
SONARR_KEY="$(read_arr_key sonarr)"
PROWLARR_KEY="$(read_arr_key prowlarr)"
BAZARR_KEY="$(read_bazarr_key)"
QBITTORRENT_USER="$(read_env_local QBITTORRENT_USER)"
QBITTORRENT_PASS="$(read_env_local QBITTORRENT_PASS)"

# Report presence (length only) without revealing anything.
for pair in "Radarr:$RADARR_KEY" "Sonarr:$SONARR_KEY" "Prowlarr:$PROWLARR_KEY" "Bazarr:$BAZARR_KEY"; do
  name="${pair%%:*}"; val="${pair#*:}"
  if [ -n "$val" ]; then info "$name API key: found (${#val} chars)"; else status warn "$name API key: NOT found — its steps will be skipped"; fi
done
if [ -n "$QBITTORRENT_USER" ] && [ -n "$QBITTORRENT_PASS" ]; then
  info "qBittorrent WebUI creds: found in .env.local"
else
  status warn "qBittorrent creds missing from .env.local — qBittorrent-dependent steps will be skipped"
fi

# ---------------------------------------------------------------------------
# Readiness — poll each service before touching it. /ping needs no auth on the
# *arr apps; qBittorrent answers its web root without a key; Bazarr answers its
# status endpoint with 401 until a key is presented (still proves reachability).
# ---------------------------------------------------------------------------
header "Waiting for services to be reachable"
RADARR_UP=0; SONARR_UP=0; PROWLARR_UP=0; QBIT_UP=0; BAZARR_UP=0
[ -n "$RADARR_KEY" ]   && { wait_for "Radarr"      "$RADARR_URL/ping"              "200"         && RADARR_UP=1   || status warn "Radarr not reachable at $RADARR_URL"; }
[ -n "$SONARR_KEY" ]   && { wait_for "Sonarr"      "$SONARR_URL/ping"              "200"         && SONARR_UP=1   || status warn "Sonarr not reachable at $SONARR_URL"; }
[ -n "$PROWLARR_KEY" ] && { wait_for "Prowlarr"    "$PROWLARR_URL/ping"            "200"         && PROWLARR_UP=1 || status warn "Prowlarr not reachable at $PROWLARR_URL"; }
{ wait_for "qBittorrent" "$QBIT_URL"                                               "200|401|403" && QBIT_UP=1     || status warn "qBittorrent not reachable at $QBIT_URL"; }
[ -n "$BAZARR_KEY" ]   && { wait_for "Bazarr"      "$BAZARR_URL/api/system/status" "200|401|403" && BAZARR_UP=1  || status warn "Bazarr not reachable at $BAZARR_URL"; }

# ===========================================================================
# 1. qBittorrent download client -> Radarr and Sonarr
# ===========================================================================
# Reusable: add qBittorrent to an *arr if not already present.
#   $1 label  $2 base url  $3 api key  $4 category field name  $5 category value
add_qbt_download_client() {
  local label="$1" base="$2" key="$3" catfield="$4" catval="$5" payload

  _curl -H "X-Api-Key: $key" "$base/api/v3/downloadclient"
  if [ "$HTTP_STATUS" != "200" ]; then
    status warn "$label: could not read download clients (HTTP $HTTP_STATUS)"; return 0
  fi
  # Match on implementation==QBittorrent with host that lowercases to 'qbittorrent'
  # (an existing entry may store the host as 'qBittorrent' with a capital B).
  if resp_has '
        [ .[] | select((.implementation // "" | ascii_downcase) == "qbittorrent")
              | .fields[]? | select(.name == "host") | (.value | tostring | ascii_downcase) ]
        | any(. == "qbittorrent")'; then
    # Already configured — still make sure remove-completed/remove-failed match
    # what we want (an older run of this script, or a manual setup, may have
    # left removeFailedDownloads on, which would delete torrents we still want
    # visible for troubleshooting). Patch in place rather than skip silently.
    local existing already_correct
    existing="$(resp_get '[.[] | select((.implementation // "" | ascii_downcase) == "qbittorrent")][0]')"
    already_correct="$(echo "$existing" | jq -r '(.removeCompletedDownloads == true) and (.removeFailedDownloads == false)')"
    if [ -n "$existing" ] && [ "$existing" != "null" ] && [ "$already_correct" != "true" ]; then
      local id want
      id="$(echo "$existing" | jq -r '.id')"
      want="$(echo "$existing" | jq '.removeCompletedDownloads = true | .removeFailedDownloads = false')"
      _curl -X PUT -H "X-Api-Key: $key" -H 'Content-Type: application/json' \
            --data "$want" "$base/api/v3/downloadclient/$id"
      case "$HTTP_STATUS" in
        200|202) status updated "$label download client: removeCompletedDownloads=true, removeFailedDownloads=false" ;;
        *)       status warn "$label: failed to update remove-completed/failed flags (HTTP $HTTP_STATUS)" ;;
      esac
      return 0
    fi
    status "exists, skipped" "$label download client (qBittorrent) already configured correctly"
    return 0
  fi

  if [ -z "$QBITTORRENT_USER" ] || [ -z "$QBITTORRENT_PASS" ]; then
    status warn "$label: qBittorrent creds unavailable — cannot add download client"; return 0
  fi

  payload="$(jq -n \
      --arg user "$QBITTORRENT_USER" --arg pass "$QBITTORRENT_PASS" \
      --arg catfield "$catfield" --arg catval "$catval" \
      '{
        name: "qBittorrent", enable: true, protocol: "torrent", priority: 1,
        # Completed+imported torrents are pure clutter (media already lives in
        # /data/media as a hardlink, see ensure_hardlink_import below), so drop
        # them automatically. Failed downloads stay so they remain visible for
        # troubleshooting instead of silently vanishing.
        removeCompletedDownloads: true, removeFailedDownloads: false,
        implementation: "QBittorrent", implementationName: "qBittorrent",
        configContract: "QBittorrentSettings", tags: [],
        fields: [
          {name:"host",  value:"qbittorrent"},
          {name:"port",  value:8080},
          {name:"useSsl", value:false},
          {name:"username", value:$user},
          {name:"password", value:$pass},
          {name:$catfield, value:$catval}
        ]
      }')"
  _curl -X POST -H "X-Api-Key: $key" -H 'Content-Type: application/json' \
        --data "$payload" "$base/api/v3/downloadclient"
  case "$HTTP_STATUS" in
    200|201|202) status created "$label download client (qBittorrent, host qbittorrent:8080, category $catval)" ;;
    *)           status warn "$label: failed to add download client (HTTP $HTTP_STATUS): $(resp_get '(.[]?.errorMessage) // .message // empty' | head -n1)" ;;
  esac
}

header "1. qBittorrent download client -> Radarr / Sonarr"
if [ "$RADARR_UP" = 1 ]; then add_qbt_download_client "Radarr" "$RADARR_URL" "$RADARR_KEY" "movieCategory" "radarr"; else status warn "Radarr skipped (unreachable / no key)"; fi
if [ "$SONARR_UP" = 1 ]; then add_qbt_download_client "Sonarr" "$SONARR_URL" "$SONARR_KEY" "tvCategory"    "tv-sonarr"; else status warn "Sonarr skipped (unreachable / no key)"; fi

# ===========================================================================
# 2. Root folders
# ===========================================================================
#   $1 label  $2 base url  $3 api key  $4 desired path
ensure_root_folder() {
  local label="$1" base="$2" key="$3" want="$4"

  _curl -H "X-Api-Key: $key" "$base/api/v3/rootfolder"
  if [ "$HTTP_STATUS" != "200" ]; then
    status warn "$label: could not read root folders (HTTP $HTTP_STATUS)"; return 0
  fi
  # Compare after stripping any trailing slash on stored paths.
  if resp_has --arg want "$want" 'any(.[]; (.path | sub("/$";"")) == $want)'; then
    status "exists, skipped" "$label root folder $want already present"
    return 0
  fi

  _curl -X POST -H "X-Api-Key: $key" -H 'Content-Type: application/json' \
        --data "$(jq -n --arg p "$want" '{path:$p}')" "$base/api/v3/rootfolder"
  case "$HTTP_STATUS" in
    200|201) status created "$label root folder $want" ;;
    400)
      # RootFolderValidator "already configured" is a benign race / re-run.
      if printf '%s' "$RESP" | grep -qi 'already configured'; then
        status "exists, skipped" "$label root folder $want already present"
      else
        status warn "$label: root folder rejected (HTTP 400): $(resp_get '(.[]?.errorMessage) // empty' | head -n1)"
      fi ;;
    *) status warn "$label: failed to add root folder (HTTP $HTTP_STATUS)" ;;
  esac
}

header "2. Root folders"
[ "$RADARR_UP" = 1 ] && ensure_root_folder "Radarr" "$RADARR_URL" "$RADARR_KEY" "/data/media/movies"
[ "$SONARR_UP" = 1 ] && ensure_root_folder "Sonarr" "$SONARR_URL" "$SONARR_KEY" "/data/media/tv"

# ===========================================================================
# 2b. Import via hardlink, not copy
# ===========================================================================
# qBittorrent's save path (/data/downloads) and the *arr root folders
# (/data/media/movies, /data/media/tv) are the SAME bind-mounted volume
# (${MEDIA_ROOT}), so a hardlink is always possible — no duplicate bytes on
# disk for a finished download. Without this, Radarr/Sonarr COPY the file
# into /data/media on import and the original stays in /data/downloads,
# doubling storage for every title until the torrent is later removed.
#   $1 label  $2 base url  $3 api key
ensure_hardlink_import() {
  local label="$1" base="$2" key="$3" cfg id want

  _curl -H "X-Api-Key: $key" "$base/api/v3/config/mediamanagement"
  if [ "$HTTP_STATUS" != "200" ]; then
    status warn "$label: could not read media management config (HTTP $HTTP_STATUS)"; return 0
  fi
  cfg="$RESP"
  if printf '%s' "$cfg" | jq -e '.copyUsingHardlinks == true' >/dev/null 2>&1; then
    status "exists, skipped" "$label already imports via hardlink"
    return 0
  fi
  id="$(printf '%s' "$cfg" | jq -r '.id')"
  want="$(printf '%s' "$cfg" | jq '.copyUsingHardlinks = true')"
  _curl -X PUT -H "X-Api-Key: $key" -H 'Content-Type: application/json' \
        --data "$want" "$base/api/v3/config/mediamanagement/$id"
  case "$HTTP_STATUS" in
    200|202) status updated "$label: import now uses hardlinks instead of copy" ;;
    *)       status warn "$label: failed to enable hardlink import (HTTP $HTTP_STATUS)" ;;
  esac
}

header "2b. Import via hardlink, not copy"
[ "$RADARR_UP" = 1 ] && ensure_hardlink_import "Radarr" "$RADARR_URL" "$RADARR_KEY"
[ "$SONARR_UP" = 1 ] && ensure_hardlink_import "Sonarr" "$SONARR_URL" "$SONARR_KEY"

# ===========================================================================
# 3. Prowlarr applications (Radarr + Sonarr, fullSync)
# ===========================================================================
# $1 impl (Radarr|Sonarr)  $2 app base url  $3 app api key  $4 extra-fields jq array
ensure_prowlarr_app() {
  local impl="$1" appurl="$2" appkey="$3" extra="$4" payload
  if printf '%s' "$APPS_BODY" | jq -e --arg i "$impl" 'any(.[]; (.implementation // "") == $i)' >/dev/null 2>&1; then
    status "exists, skipped" "Prowlarr application '$impl' already registered"
    return 0
  fi
  if [ -z "$appkey" ]; then
    status warn "Prowlarr: $impl API key unavailable — cannot register application"; return 0
  fi
  payload="$(jq -n \
      --arg name "$impl" --arg base "$appurl" --arg key "$appkey" \
      --argjson extra "$extra" \
      '{
        name: $name, implementation: $name, implementationName: $name,
        configContract: ($name + "Settings"),
        syncLevel: "fullSync", enable: true, tags: [],
        fields: ([
          {name:"prowlarrUrl", value:"http://prowlarr:9696"},
          {name:"baseUrl",     value:$base},
          {name:"apiKey",      value:$key}
        ] + $extra)
      }')"
  _curl -X POST -H "X-Api-Key: $PROWLARR_KEY" -H 'Content-Type: application/json' \
        --data "$payload" "$PROWLARR_URL/api/v1/applications"
  case "$HTTP_STATUS" in
    200|201) status created "Prowlarr application '$impl' (fullSync -> $appurl)" ;;
    *)       status warn "Prowlarr: failed to add '$impl' (HTTP $HTTP_STATUS): $(resp_get '(.[]?.errorMessage) // .message // empty' | head -n1)" ;;
  esac
}

header "3. Prowlarr applications (fullSync)"
if [ "$PROWLARR_UP" = 1 ]; then
  _curl -H "X-Api-Key: $PROWLARR_KEY" "$PROWLARR_URL/api/v1/applications"
  APPS_BODY="$RESP"
  if [ "$HTTP_STATUS" != "200" ]; then
    status warn "Prowlarr: could not read applications (HTTP $HTTP_STATUS)"
    APPS_BODY="[]"
  fi
  ensure_prowlarr_app "Radarr" "http://radarr:7878" "$RADARR_KEY" \
    '[{"name":"syncCategories","value":[2000,2010,2020,2030,2040,2045,2050,2060,2070,2080,2090]}]'
  ensure_prowlarr_app "Sonarr" "http://sonarr:8989" "$SONARR_KEY" \
    '[{"name":"syncCategories","value":[5000,5010,5020,5030,5040,5045,5050,5090]},{"name":"animeSyncCategories","value":[5070]},{"name":"syncAnimeStandardFormatSearch","value":true}]'
else
  status warn "Prowlarr unreachable / no key — skipping application registration"
fi

# ===========================================================================
# 4. qBittorrent WebUI creds + default save path /data/downloads
# ===========================================================================
header "4. qBittorrent (credential check + save path)"
if [ "$QBIT_UP" != 1 ]; then
  status warn "qBittorrent unreachable — skipping"
elif [ -z "$QBITTORRENT_USER" ] || [ -z "$QBITTORRENT_PASS" ]; then
  status warn "qBittorrent creds missing from .env.local — skipping"
else
  JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT
  # A successful login (HTTP 204, or legacy 200 "Ok.") IS the idempotency signal:
  # it proves the live WebUI creds already match .env.local. web_ui_password can
  # never be read back, and rewriting it would kill the session and overwrite
  # user config — so we confirm rather than force-set.
  _curl -c "$JAR" -H "Referer: $QBIT_URL" \
      --data-urlencode "username=$QBITTORRENT_USER" \
      --data-urlencode "password=$QBITTORRENT_PASS" \
      "$QBIT_URL/api/v2/auth/login"
  login_clean="${RESP//[$'\r\n\t ']/}"
  if { [ "$HTTP_STATUS" = "204" ] || [ "$HTTP_STATUS" = "200" ]; } && [ "$login_clean" != "Fails." ]; then
    status "exists, skipped" "qBittorrent WebUI creds already aligned with .env.local (login OK)"

    # Default save path.
    _curl -b "$JAR" -H "Referer: $QBIT_URL" "$QBIT_URL/api/v2/app/preferences"
    cur_path=""
    [ "$HTTP_STATUS" = "200" ] && cur_path="$(resp_get '.save_path // empty')"
    if [ "$cur_path" = "/data/downloads" ]; then
      status "exists, skipped" "qBittorrent save path already /data/downloads"
    else
      _curl -b "$JAR" -H "Referer: $QBIT_URL" \
        --data-urlencode 'json={"save_path":"/data/downloads"}' \
        "$QBIT_URL/api/v2/app/setPreferences"
      set_code="$HTTP_STATUS"
      # Confirm by re-reading.
      _curl -b "$JAR" -H "Referer: $QBIT_URL" "$QBIT_URL/api/v2/app/preferences"
      new_path="$(resp_get '.save_path // empty')"
      if [ "$new_path" = "/data/downloads" ]; then
        status created "qBittorrent default save path -> /data/downloads (was ${cur_path:-unknown})"
      else
        status warn "qBittorrent: save path not confirmed (setPreferences HTTP $set_code, now '${new_path:-?}')"
      fi
    fi
  else
    status warn "qBittorrent login FAILED (HTTP $HTTP_STATUS). WebUI creds do not match .env.local."
    info "Manual fix: get the temp password via 'docker logs watchparty-qbittorrent',"
    info "log in at $QBIT_URL, then Settings > Web UI > set username/password to match .env.local."
  fi
fi

# ===========================================================================
# 5. Bazarr -> Radarr + Sonarr
# ===========================================================================
header "5. Bazarr subtitle provider links"
if [ "$BAZARR_UP" != 1 ]; then
  status warn "Bazarr unreachable / no key — skipping"
elif [ -z "$RADARR_KEY" ] && [ -z "$SONARR_KEY" ]; then
  status warn "Bazarr: neither Radarr nor Sonarr key available — skipping"
else
  _curl -H "X-API-KEY: $BAZARR_KEY" "$BAZARR_URL/api/system/settings"
  if [ "$HTTP_STATUS" != "200" ]; then
    status warn "Bazarr: could not read settings (HTTP $HTTP_STATUS) — skipping"
  else
    # Already-connected iff enabled AND key set AND ip/port match the container names.
    r_ok="$(resp_get 'if (.general.use_radarr==true) and ((.radarr.apikey // "")|length>0) and (.radarr.ip=="radarr") and ((.radarr.port|tostring)=="7878") then "yes" else "no" end')"
    s_ok="$(resp_get 'if (.general.use_sonarr==true) and ((.sonarr.apikey // "")|length>0) and (.sonarr.ip=="sonarr") and ((.sonarr.port|tostring)=="8989") then "yes" else "no" end')"
    [ -z "$r_ok" ] && r_ok=no
    [ -z "$s_ok" ] && s_ok=no

    # Build a single form-encoded POST containing only the not-yet-connected
    # sections (Bazarr expects application/x-www-form-urlencoded, NOT JSON).
    bz_args=()
    if [ "$r_ok" = yes ]; then
      status "exists, skipped" "Bazarr already linked to Radarr"
    elif [ -z "$RADARR_KEY" ]; then
      status warn "Bazarr: Radarr key unavailable — cannot link Radarr"
    else
      bz_args+=(--data-urlencode "settings-general-use_radarr=true"
                --data-urlencode "settings-radarr-ip=radarr"
                --data-urlencode "settings-radarr-port=7878"
                --data-urlencode "settings-radarr-base_url=/"
                --data-urlencode "settings-radarr-ssl=false"
                --data-urlencode "settings-radarr-apikey=$RADARR_KEY")
    fi
    if [ "$s_ok" = yes ]; then
      status "exists, skipped" "Bazarr already linked to Sonarr"
    elif [ -z "$SONARR_KEY" ]; then
      status warn "Bazarr: Sonarr key unavailable — cannot link Sonarr"
    else
      bz_args+=(--data-urlencode "settings-general-use_sonarr=true"
                --data-urlencode "settings-sonarr-ip=sonarr"
                --data-urlencode "settings-sonarr-port=8989"
                --data-urlencode "settings-sonarr-base_url=/"
                --data-urlencode "settings-sonarr-ssl=false"
                --data-urlencode "settings-sonarr-apikey=$SONARR_KEY")
    fi

    if [ "${#bz_args[@]}" -gt 0 ]; then
      _curl -X POST -H "X-API-KEY: $BAZARR_KEY" "${bz_args[@]}" "$BAZARR_URL/api/system/settings"
      post_code="$HTTP_STATUS"
      if [ "$post_code" = "204" ] || [ "$post_code" = "200" ]; then
        # Verify: radarr_version / sonarr_version become non-empty once linked.
        _curl -H "X-API-KEY: $BAZARR_KEY" "$BAZARR_URL/api/system/status"
        rv="$(resp_get '(.data.radarr_version // .radarr_version) // ""')"
        sv="$(resp_get '(.data.sonarr_version // .sonarr_version) // ""')"
        if [ "$r_ok" != yes ] && [ -n "$RADARR_KEY" ]; then
          [ -n "$rv" ] && status created "Bazarr linked to Radarr (radarr_version=$rv)" || status warn "Bazarr: Radarr link not confirmed (radarr_version empty)"
        fi
        if [ "$s_ok" != yes ] && [ -n "$SONARR_KEY" ]; then
          [ -n "$sv" ] && status created "Bazarr linked to Sonarr (sonarr_version=$sv)" || status warn "Bazarr: Sonarr link not confirmed (sonarr_version empty)"
        fi
      elif [ "$post_code" = "406" ]; then
        status warn "Bazarr: settings validation failed (HTTP 406) — previous config kept, nothing corrupted"
      else
        status warn "Bazarr: settings POST returned HTTP $post_code"
      fi
    fi
  fi
fi

# ===========================================================================
# Summary + the one remaining manual step.
# ===========================================================================
header "Summary"
for line in "${SUMMARY[@]}"; do printf '  %s\n' "$line"; done

warn_count=0
for line in "${SUMMARY[@]}"; do [[ "$line" == "[warn]"* ]] && warn_count=$((warn_count+1)); done

header "Next step (manual — the only thing left)"
cat <<'EOF'
  Add your indexers in Prowlarr:  Settings > Indexers > Add Indexer.
  Because Radarr and Sonarr are registered as fullSync applications, every
  indexer you add in Prowlarr AUTO-SYNCS to both — no per-app indexer setup.
EOF

if [ "$warn_count" -gt 0 ]; then
  printf '\n%sFinished with %d warning(s) — review the [warn] lines above.%s\n' "$C_WARN" "$warn_count" "$C_RST"
else
  printf '\n%sAll steps complete. The Servarr stack is wired.%s\n' "$C_OK" "$C_RST"
fi
