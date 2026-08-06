#!/usr/bin/env bash
# Restrict the production stack's administrative ports to private access only.
#
# WHY THIS EXISTS, AND WHY ufw ALONE IS NOT ENOUGH
#
# docker-compose.prod.yml publishes the admin UIs on 0.0.0.0 so they stay
# reachable over Tailscale. That means the ONLY thing keeping them off the
# public internet is this script. Treat it as part of the deploy, not as
# optional hardening.
#
# Docker DNATs published container ports in nat/PREROUTING, so those packets are
# routed (FORWARD), never delivered locally (INPUT). ufw manages INPUT. This is
# why `ufw deny 8096` does NOT block traffic to a published container port — a
# common and very quiet misconfiguration. Docker provides the DOCKER-USER chain
# for exactly this: it is consulted from FORWARD before Docker's own accept
# rules, and Docker never flushes rules inside it.
#
# WHY IT DROPS ON THE PUBLIC INTERFACE RATHER THAN "NOT tailscale0"
#
# The obvious formulation — drop admin ports arriving on any interface that is
# not tailscale0 — is wrong, and quietly breaks the stack. Container-to-container
# traffic on watchparty-net also traverses FORWARD/DOCKER-USER, with a docker
# bridge (br-*) as the ingress interface. A blanket "not tailscale0" DROP would
# therefore also drop the app's own calls to sonarr:8989, radarr:7878,
# prowlarr:9696 and bazarr:6767. Matching the public interface explicitly keeps
# private and inter-container paths untouched.
#
# Usage:
#   sudo ./deploy/firewall.sh            # apply (idempotent)
#   sudo ./deploy/firewall.sh --verify   # check only; nonzero if rules missing
#   PUBLIC_IFACE=ens3 sudo ./deploy/firewall.sh    # override detection

set -euo pipefail

# Ports that must never be reachable from the public internet. Keep in sync with
# the published admin ports in docker-compose.prod.yml.
#   8096 jellyfin | 8989 sonarr | 7878 radarr | 6767 bazarr
#   9696 prowlarr | 8080 qbittorrent | 3001 watchparty (direct/admin access)
ADMIN_PORTS="8096,8989,7878,6767,9696,8080,3001"

# Deliberately NOT restricted — remote party members need these:
#   80,443/tcp          Caddy (public site)
#   7881/tcp            LiveKit ICE/TCP
#   7882/udp            LiveKit ICE/UDP (single-port mux, see secrets/livekit.yaml)
#   3478/udp 5349/tcp   coturn TURN (network_mode: host, so never DNAT'd here)
#   6881/tcp+udp        qBittorrent BitTorrent peer port
#
# LiveKit's 7880 (HTTP/WS signalling) is not published by compose at all, so it
# needs no rule. If it is ever published, add it to ADMIN_PORTS.

CHAIN="DOCKER-USER"
COMMENT="watchparty-admin-restrict"
RULES_V4="/etc/iptables/rules.v4"
RULES_V6="/etc/iptables/rules.v6"

log()  { printf '%s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_root() { [ "$(id -u)" -eq 0 ] || die "must run as root (use sudo)."; }

# ── Resolve the public interface ───────────────────────────────────────────
# Detected rather than hard-coded: a wrong interface name produces rules that
# match nothing, silently protecting nothing while appearing to succeed. If it
# cannot be determined, abort rather than write a useless ruleset.
detect_public_iface() {
  if [ -n "${PUBLIC_IFACE:-}" ]; then
    ip link show "$PUBLIC_IFACE" >/dev/null 2>&1 \
      || die "PUBLIC_IFACE=$PUBLIC_IFACE does not exist on this host."
    printf '%s' "$PUBLIC_IFACE"; return
  fi
  local found
  found="$(ip -o route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')"
  [ -n "$found" ] || die "could not determine the default-route interface. \
Set PUBLIC_IFACE=<iface> explicitly. Refusing to write rules that would match nothing."
  case "$found" in
    tailscale*|lo|docker*|br-*)
      die "default route is via '$found', which is not a public interface. \
Set PUBLIC_IFACE=<iface> explicitly." ;;
  esac
  printf '%s' "$found"
}

# Advisory only: losing Tailscale means losing admin access once these rules are
# in place. Not fatal — the rules are still correct.
check_private_path() {
  ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | cut -d@ -f1 \
    | grep -qE '^tailscale[0-9]*$' \
    || warn "no Tailscale interface found. These rules will block the admin ports
         from the public interface, so make sure you have another private route
         (Tailscale, VPN, or SSH port-forward) before relying on this host."
}

ipt_bins() {
  printf 'iptables\n'
  # Docker only creates DOCKER-USER in ip6tables when IPv6 is enabled for it.
  if command -v ip6tables >/dev/null 2>&1 && ip6tables -S "$CHAIN" >/dev/null 2>&1; then
    printf 'ip6tables\n'
  fi
}

# Matches our marker whether or not iptables quoted it. iptables-save only wraps
# a comment in quotes when it contains whitespace, so a pattern hard-coding
# quotes silently matches nothing — which would make purge a no-op and let rules
# stack on every re-run.
marker_re() { printf -- '--comment "?%s"?' "$COMMENT"; }

# Deletes by rule NUMBER rather than by replaying the rule spec. Replaying a
# spec parsed out of `-S` is fragile: it has to be word-split unquoted, so any
# quoting in the original (comments, multiport lists) is corrupted and the -D
# quietly fails to match. Numbers are unambiguous. Descending order keeps
# earlier indices valid as later ones are removed.
purge_rules() {
  local bin="$1" n=0 i
  local -a nums=()
  while IFS= read -r i; do nums+=("$i"); done < <(
    $bin -S "$CHAIN" 2>/dev/null | sed -n "s/^-A $CHAIN //p" \
      | grep -nE -- "$(marker_re)" | cut -d: -f1 | sort -rn
  )
  for i in "${nums[@]}"; do
    $bin -D "$CHAIN" "$i"
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] && log "  $bin: removed $n stale rule(s)."
  return 0
}

count_rules() {
  local bin="$1"
  $bin -S "$CHAIN" 2>/dev/null | grep -cE -- "$(marker_re)" || true
}

apply_rules() {
  local iface="$1" bin
  for bin in $(ipt_bins); do
    # Purge first so re-running cannot stack duplicates — that is what the
    # comment marker is for.
    purge_rules "$bin"
    $bin -I "$CHAIN" 1 -i "$iface" -p tcp -m multiport --dports "$ADMIN_PORTS" \
      -m comment --comment "$COMMENT" -j DROP
    log "  $bin: admin ports dropped on $iface."
  done
}

persist_rules() {
  local ok=1
  if command -v netfilter-persistent >/dev/null 2>&1 || command -v iptables-save >/dev/null 2>&1; then
    mkdir -p "$(dirname "$RULES_V4")"
    iptables-save > "$RULES_V4" || ok=0
    if command -v ip6tables-save >/dev/null 2>&1 && ip6tables -S "$CHAIN" >/dev/null 2>&1; then
      ip6tables-save > "$RULES_V6" || ok=0
    fi
  else
    ok=0
  fi

  if [ "$ok" = 1 ] && command -v netfilter-persistent >/dev/null 2>&1; then
    log "  saved to $RULES_V4 (netfilter-persistent restores at boot)."
    return 0
  fi

  cat >&2 <<'EOF'
WARNING: rules are active NOW but are NOT persisted, so a reboot will silently
         re-expose every admin port. Install persistence, then re-run:

             sudo apt-get install -y iptables-persistent
             sudo ./deploy/firewall.sh
             sudo ./deploy/firewall.sh --verify
EOF
  return 1
}

verify() {
  local iface bin n rc=0
  iface="$(detect_public_iface)"

  for bin in $(ipt_bins); do
    n="$(count_rules "$bin")"
    if [ "$n" -lt 1 ]; then
      printf 'FAIL: no %s rule in %s/%s. Run: sudo %s\n' \
        "$COMMENT" "$bin" "$CHAIN" "$0" >&2
      rc=1; continue
    fi
    if ! $bin -S "$CHAIN" | grep -E -- "$(marker_re)" | grep -q -- "-j DROP"; then
      printf 'FAIL: %s has a marker rule but no DROP — admin ports are NOT protected.\n' "$bin" >&2
      rc=1; continue
    fi
    if ! $bin -S "$CHAIN" | grep -E -- "$(marker_re)" | grep -q -- "-i $iface"; then
      printf 'FAIL: %s DROP rule does not match the public interface %s.\n' "$bin" "$iface" >&2
      rc=1; continue
    fi
    printf 'OK: %s drops admin ports %s on %s.\n' "$bin" "$ADMIN_PORTS" "$iface"
  done

  # Both halves are required. A saved rules file with nothing to replay it at
  # boot is not persistence — without this second check, verify would report
  # "persisted" on a host that silently re-exposes every admin port after a
  # reboot, contradicting the warning apply already printed.
  if [ ! -f "$RULES_V4" ] || ! grep -q -- "$COMMENT" "$RULES_V4" 2>/dev/null; then
    printf 'FAIL: %s does not contain the admin rules — a reboot re-exposes the admin ports.\n' \
      "$RULES_V4" >&2
    rc=1
  elif ! command -v netfilter-persistent >/dev/null 2>&1; then
    printf 'FAIL: %s exists but iptables-persistent is not installed, so nothing
      replays it at boot. Install it: sudo apt-get install -y iptables-persistent\n' \
      "$RULES_V4" >&2
    rc=1
  else
    printf 'OK: rules persisted in %s and iptables-persistent will restore them.\n' "$RULES_V4"
  fi
  return "$rc"
}

main() {
  case "${1:-apply}" in
    --verify|-v|verify)
      require_root
      verify
      ;;
    apply|"")
      require_root
      local iface
      iface="$(detect_public_iface)"
      log "Public interface: $iface"
      check_private_path
      apply_rules "$iface"
      persist_rules || true
      log ""
      verify
      ;;
    --help|-h)
      sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'
      ;;
    *)
      die "unknown argument: $1 (expected --verify, --help, or no argument)"
      ;;
  esac
}

main "$@"
