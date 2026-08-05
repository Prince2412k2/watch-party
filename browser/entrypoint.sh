#!/usr/bin/env bash
# Boots the resident half of the shared browser: a virtual display, a window
# manager, an audio loopback, and the control agent. It deliberately starts NO
# browser — a party asks for one over the agent's API, and closing it leaves this
# container idle at near-zero CPU (the whole point of keeping it resident).
set -euo pipefail

: "${DISPLAY:=:99}"
: "${SCREEN_W:=1280}"
: "${SCREEN_H:=720}"
: "${AGENT_PORT:=8080}"
: "${PROFILE_ROOT:=/profiles}"
: "${BROWSER_AGENT_TOKEN:?BROWSER_AGENT_TOKEN is required — the agent refuses every request without one}"
: "${BROWSER_TARGET_TOKEN:?BROWSER_TARGET_TOKEN is required and must differ from BROWSER_AGENT_TOKEN}"
[[ "$BROWSER_TARGET_TOKEN" != "$BROWSER_AGENT_TOKEN" ]] || { echo "browser tokens must differ" >&2; exit 1; }
agent_token=$BROWSER_AGENT_TOKEN
target_token=$BROWSER_TARGET_TOKEN
unset BROWSER_AGENT_TOKEN BROWSER_TARGET_TOKEN

export DISPLAY
log() { echo "[browser] $*" >&2; }

mkdir -p "$XDG_RUNTIME_DIR" /tmp/browser-home
chmod 700 "$XDG_RUNTIME_DIR" /tmp/browser-home
export HOME=/tmp/browser-home

cleanup() { pkill -P $$ 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# --- virtual display ---------------------------------------------------------
export XAUTHORITY=/tmp/browser-xauthority
touch "$XAUTHORITY"
chmod 600 "$XAUTHORITY"
xauth -f "$XAUTHORITY" add "$DISPLAY" . "$(mcookie)"
# -extension RANDR is load-bearing, not tidying. Xvfb advertises RANDR 1.6 but
# exposes no CRTC or output behind it. Chromium's ScreenCapturerX11 takes the
# XRandR path whenever the extension is present and then enumerates monitors, so
# SelectSource("screen:0:0") finds nothing and returns false — surfacing in the
# page as a bare "NotReadableError: Could not start video source" long after the
# capturer has otherwise initialised (SHM and XRandR both report fine first).
# With RANDR off the capturer falls back to grabbing the root window, which works.
Xvfb "$DISPLAY" -auth "$XAUTHORITY" -screen 0 "${SCREEN_W}x${SCREEN_H}x24" -nolisten tcp -dpi 96 -extension RANDR &
for _ in $(seq 1 60); do
  xdpyinfo >/dev/null 2>&1 && break
  sleep 0.1
done
xdpyinfo >/dev/null 2>&1 || { log "FATAL: Xvfb never came up"; exit 1; }

# Without a window manager there is no input focus, so injected keystrokes land
# nowhere and fullscreen requests are ignored.
matchbox-window-manager -use_titlebar no >/dev/null 2>&1 &
sleep 0.5

cp "$XAUTHORITY" /tmp/target-authority-bootstrap
XAUTHORITY=/tmp/target-authority-bootstrap \
  xauth -f /tmp/target-authority-bootstrap generate "$DISPLAY" . untrusted timeout 86400
target_authority=$(xauth -f /tmp/target-authority-bootstrap nlist "$DISPLAY")
[[ -n "$target_authority" ]] || { log "FATAL: could not create target X11 authorization"; exit 1; }
# FamilyWild lets the cookie survive the container-hostname boundary. The X
# server still records this generated authorization as untrusted.
rm -f /target-xauth/authority
printf 'ffff%s\n' "${target_authority:4}" | xauth -f /target-xauth/authority nmerge -
rm -f /tmp/target-authority-bootstrap
chmod 600 /target-xauth/authority
# Xsecurity expires generated authorizations only while no client uses them.
# This root-window listener keeps the target cookie valid across idle days.
XAUTHORITY=/target-xauth/authority xev -root >/dev/null 2>&1 &
target_auth_keeper=$!
sleep 0.1
kill -0 "$target_auth_keeper" 2>/dev/null \
  || { log "FATAL: target X11 authorization is unusable"; exit 1; }
log "Xvfb up on $DISPLAY at ${SCREEN_W}x${SCREEN_H}"

# --- audio loopback ----------------------------------------------------------
# getDisplayMedia on Linux does not hand back system audio, so the publisher
# takes it from a null sink's monitor via getUserMedia instead.
dd if=/dev/urandom of=/pulse/cookie bs=256 count=1 status=none
chmod 600 /pulse/cookie
export PULSE_COOKIE=/pulse/cookie
# The remap is required because Chromium filters monitor sources from its input
# list. Loading these modules only from the startup file lets the daemon reject
# module administration from the untrusted target afterward.
printf '%s\n' \
  'load-module module-native-protocol-unix socket=/pulse/native auth-anonymous=0 auth-cookie=/pulse/cookie' \
  'load-module module-null-sink sink_name=wp_sink' \
  'load-module module-remap-source source_name=wp_mic master=wp_sink.monitor' \
  'set-default-sink wp_sink' \
  'set-default-source wp_mic' \
  > /tmp/pulse.pa
if pulseaudio --daemonize=yes --exit-idle-time=-1 --disallow-module-loading \
  --file=/tmp/pulse.pa >/dev/null 2>&1; then
  log "pulseaudio up; default source = wp_mic (remapped from wp_sink.monitor)"
else
  log "WARN: pulseaudio failed to start — the browser will publish video without audio"
fi

mkdir -p "$PROFILE_ROOT"
# A container recreate must not inherit a previous session's cookies even if the
# tmpfs mount is ever dropped from compose.
rm -rf "${PROFILE_ROOT:?}"/* 2>/dev/null || true

log "starting control agent on 0.0.0.0:${AGENT_PORT}"
exec env BROWSER_AGENT_TOKEN="$agent_token" BROWSER_TARGET_TOKEN="$target_token" \
  python3 /opt/browser/agent.py
