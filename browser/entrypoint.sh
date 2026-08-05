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

export DISPLAY
log() { echo "[browser] $*" >&2; }

# --- optional TLS-inspection CA ----------------------------------------------
# Some corporate networks MITM HTTPS, which breaks sites inside the container
# while leaving the host fine (the appliance presents only a leaf cert, so it
# cannot be recovered from the connection — you have to get the CA from IT).
# Irrelevant on a VPS; mount a .crt here if a developer hits it locally.
if compgen -G "/opt/browser/extra-ca/*.crt" >/dev/null 2>&1; then
  cp /opt/browser/extra-ca/*.crt /usr/local/share/ca-certificates/ 2>/dev/null || true
  update-ca-certificates >/dev/null 2>&1 || true
  # Chromium on Linux may consult its own NSS store rather than /etc/ssl, so add
  # the CA to both. Doing only one of these silently fails half the time.
  mkdir -p /root/.pki/nssdb
  [ -f /root/.pki/nssdb/cert9.db ] || certutil -d sql:/root/.pki/nssdb -N --empty-password >/dev/null 2>&1 || true
  for cert in /opt/browser/extra-ca/*.crt; do
    certutil -d sql:/root/.pki/nssdb -A -t "C,," -n "$(basename "$cert")" -i "$cert" >/dev/null 2>&1 || true
  done
  log "installed extra CA(s): $(ls /opt/browser/extra-ca/*.crt | xargs -n1 basename | tr '\n' ' ')"
fi

cleanup() { pkill -P $$ 2>/dev/null || true; }
trap cleanup EXIT INT TERM

# --- virtual display ---------------------------------------------------------
# -extension RANDR is load-bearing, not tidying. Xvfb advertises RANDR 1.6 but
# exposes no CRTC or output behind it. Chromium's ScreenCapturerX11 takes the
# XRandR path whenever the extension is present and then enumerates monitors, so
# SelectSource("screen:0:0") finds nothing and returns false — surfacing in the
# page as a bare "NotReadableError: Could not start video source" long after the
# capturer has otherwise initialised (SHM and XRandR both report fine first).
# With RANDR off the capturer falls back to grabbing the root window, which works.
Xvfb "$DISPLAY" -screen 0 "${SCREEN_W}x${SCREEN_H}x24" -nolisten tcp -dpi 96 -extension RANDR &
for _ in $(seq 1 60); do
  xdpyinfo >/dev/null 2>&1 && break
  sleep 0.1
done
xdpyinfo >/dev/null 2>&1 || { log "FATAL: Xvfb never came up"; exit 1; }
log "Xvfb up on $DISPLAY at ${SCREEN_W}x${SCREEN_H}"

# Without a window manager there is no input focus, so injected keystrokes land
# nowhere and fullscreen requests are ignored.
matchbox-window-manager -use_titlebar no >/dev/null 2>&1 &
sleep 0.5

# --- audio loopback ----------------------------------------------------------
# getDisplayMedia on Linux does not hand back system audio, so the publisher
# takes it from a null sink's monitor via getUserMedia instead.
if pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1; then
  pactl load-module module-null-sink sink_name=wp_sink >/dev/null 2>&1 || true
  pactl set-default-sink wp_sink >/dev/null 2>&1 || true
  # The remap is required, not cosmetic. Chromium filters PulseAudio *monitor*
  # sources out of its input list — they aren't microphones — so pointing the
  # default source straight at wp_sink.monitor yields "NotFoundError: Requested
  # device not found" with zero audioinput devices enumerated.
  # module-remap-source republishes the monitor as an ordinary source, which
  # Chromium will list and open.
  pactl load-module module-remap-source source_name=wp_mic \
    master=wp_sink.monitor >/dev/null 2>&1 || true
  pactl set-default-source wp_mic >/dev/null 2>&1 || true
  log "pulseaudio up; default source = wp_mic (remapped from wp_sink.monitor)"
else
  log "WARN: pulseaudio failed to start — the browser will publish video without audio"
fi

mkdir -p "$PROFILE_ROOT"
# A container recreate must not inherit a previous session's cookies even if the
# tmpfs mount is ever dropped from compose.
rm -rf "${PROFILE_ROOT:?}"/* 2>/dev/null || true

log "starting control agent on 0.0.0.0:${AGENT_PORT}"
exec python3 /opt/browser/agent.py
