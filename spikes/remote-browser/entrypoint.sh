#!/usr/bin/env bash
# Boots a virtual display, a browser showing TARGET_URL, and a second browser
# window running publisher/ which captures the first and publishes it into an
# existing LiveKit room. Chromium owns capture, encode and WebRTC; nothing here
# speaks RTP.
set -euo pipefail

: "${DISPLAY:=:99}"
: "${SCREEN_W:=1280}"
: "${SCREEN_H:=720}"
: "${SCREEN_FPS:=30}"
: "${CAPTURE_MODE:=screen}"      # screen | tab
: "${CODEC:=vp8}"
: "${MAX_BITRATE_KBPS:=2500}"
: "${DESKTOP_SOURCE:=Entire screen}"
: "${BROWSER_CHROME:=full}"       # full = tab strip + address bar | kiosk = page only
: "${TARGET_TITLE:=}"            # tab mode only: substring of the target tab title
: "${TARGET_URL:?TARGET_URL is required}"
: "${LIVEKIT_URL:?LIVEKIT_URL is required}"
: "${LIVEKIT_TOKEN:?LIVEKIT_TOKEN is required (run ./probe.sh token)}"

export DISPLAY
log() { echo "[entrypoint] $*" >&2; }

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

# A window manager is not optional: without one there is no input focus, so
# injected keystrokes land nowhere and fullscreen requests are ignored.
matchbox-window-manager -use_titlebar no >/dev/null 2>&1 &
sleep 0.5

# --- audio -------------------------------------------------------------------
# Only screen mode needs this. getDisplayMedia on Linux does not hand back
# system audio, so the publisher takes it from a null sink's monitor via
# getUserMedia instead. Tab capture carries the tab's own audio and ignores all
# of this.
if [ "$CAPTURE_MODE" = "screen" ]; then
  if pulseaudio --start --exit-idle-time=-1 >/dev/null 2>&1; then
    pactl load-module module-null-sink sink_name=spike_sink >/dev/null 2>&1 || true
    pactl set-default-sink spike_sink >/dev/null 2>&1 || true
    # The remap is required, not cosmetic. Chromium filters PulseAudio *monitor*
    # sources out of its input list — they aren't microphones — so pointing the
    # default source straight at spike_sink.monitor yields
    # "NotFoundError: Requested device not found" with zero audioinput devices
    # enumerated. module-remap-source republishes the monitor as an ordinary
    # source, which Chromium will list and open.
    pactl load-module module-remap-source source_name=spike_mic \
      master=spike_sink.monitor >/dev/null 2>&1 || true
    pactl set-default-source spike_mic >/dev/null 2>&1 || true
    log "pulseaudio up; default source = spike_mic (remapped from spike_sink.monitor)"
  else
    log "WARN: pulseaudio failed to start — record the audio probe as N/A"
  fi
fi

# --- serve the publisher over http://localhost --------------------------------
# getDisplayMedia and getUserMedia refuse to run outside a secure context, and
# localhost counts as one. file:// does not.
( cd /opt/spike/publisher && exec python3 -m http.server 9000 --bind 127.0.0.1 ) \
  >/dev/null 2>&1 &
for _ in $(seq 1 60); do
  curl -sf -o /dev/null http://127.0.0.1:9000/publisher.html && break
  sleep 0.1
done
log "publisher served on http://127.0.0.1:9000"

# --- publish the viewer on 0.0.0.0 so the host can open it ------------------
# Bound to 0.0.0.0 and port-published by compose. The token is baked into the page
# here rather than passed in the query string, so the operator opens a bare URL.
if [ -n "${VIEWER_TOKEN:-}" ]; then
  mkdir -p /opt/spike/viewerroot
  cp /opt/spike/publisher/viewer/livekit-client.umd.js /opt/spike/viewerroot/ 2>/dev/null || true
  python3 - <<PYEOF
import json, pathlib
src = pathlib.Path('/opt/spike/publisher/viewer/viewer.html').read_text()
cfg = json.dumps({'lk': """${VIEWER_LK_URL}""", 'token': """${VIEWER_TOKEN}""",
                  'room': 'spike'})
tag = '<script src="./livekit-client.umd.js"></script>'
out = src.replace(tag, '<script>window.__SPIKE = %s</script>\n%s' % (cfg, tag))
pathlib.Path('/opt/spike/viewerroot/index.html').write_text(out)
PYEOF
  # Not http.server: that can only serve files, so the stream was watchable but
  # not touchable. viewer-server.py adds POST /input -> xdotool.
  VIEWER_ROOT=/opt/spike/viewerroot SCREEN_W="$SCREEN_W" SCREEN_H="$SCREEN_H" \
    DISPLAY="$DISPLAY" python3 /opt/spike/viewer-server.py >/dev/null 2>&1 &
  log "viewer published on 0.0.0.0:8899 (open http://localhost:${VIEWER_PORT:-8899}/ on the host)"
else
  log "VIEWER_TOKEN unset — viewer page not served"
fi

PUB_QS="lk=$(printf %s "$LIVEKIT_URL" | sed 's/&/%26/g')"
PUB_QS="${PUB_QS}&token=${LIVEKIT_TOKEN}"
PUB_QS="${PUB_QS}&mode=${CAPTURE_MODE}&codec=${CODEC}&kbps=${MAX_BITRATE_KBPS}"
PUB_QS="${PUB_QS}&fps=${SCREEN_FPS}&w=${SCREEN_W}&h=${SCREEN_H}"
PUB_URL="http://127.0.0.1:9000/publisher.html?${PUB_QS}"

COMMON=(
  --no-sandbox
  --no-first-run
  --no-default-browser-check
  --disable-search-engine-choice-screen
  --disable-features=Translate,MediaRouter,AcceptCHFrame
  --autoplay-policy=no-user-gesture-required
  --use-fake-ui-for-media-stream
  # Without --test-type the "unsupported command-line flag: --no-sandbox" infobar
  # sits across the top ~50px of the display and lands in the capture.
  --test-type
  --disable-infobars
  --hide-scrollbars
  # The publisher window is deliberately stacked behind the fullscreen target, so
  # it is occluded. These keep Chromium from throttling it on that basis. Measured
  # note: occlusion turned out NOT to be the cause of the 15fps we chased (that
  # was livekit-client's screen-share preset — see publisher.js). Kept as hygiene
  # for a permanently-hidden publisher, not as a fix.
  --disable-backgrounding-occluded-windows
  --disable-renderer-backgrounding
  --disable-background-timer-throttling
  --enable-logging=stderr
  --v=0
)

if [ "$CAPTURE_MODE" = "tab" ]; then
  # One browser instance, two tabs: the publisher grabs the target tab by title.
  # Cheaper than screen capture (no framebuffer round-trip) and audio rides
  # along with the tab, but it needs a title it can match.
  [ -n "$TARGET_TITLE" ] || { log "FATAL: CAPTURE_MODE=tab requires TARGET_TITLE"; exit 1; }
  log "tab capture, selecting tab by title: '$TARGET_TITLE'"
  chromium "${COMMON[@]}" \
    --user-data-dir=/tmp/prof-main \
    --window-size="${SCREEN_W},${SCREEN_H}" \
    --window-position=0,0 \
    --auto-select-tab-capture-source-by-title="$TARGET_TITLE" \
    "$TARGET_URL" &
  sleep 4
  chromium --user-data-dir=/tmp/prof-main --new-window "$PUB_URL" >/dev/null 2>&1 || true
else
  # Two independent browsers. The publisher starts FIRST and small, the target
  # second at full screen size, so the target is stacked above the publisher and
  # a whole-screen grab sees only the target.
  log "screen capture, desktop source: '$DESKTOP_SOURCE'"
  chromium "${COMMON[@]}" \
    --user-data-dir=/tmp/prof-pub \
    --window-size=480,320 \
    --window-position=0,0 \
    --auto-select-desktop-capture-source="$DESKTOP_SOURCE" \
    "$PUB_URL" &
  sleep 4
  # BROWSER_CHROME=full keeps Chromium's own tab strip and address bar in the
  # capture, which is what a "remote browser" is supposed to look like — you can
  # see and drive the tabs. kiosk hides all of it and streams only the page, which
  # is what you want when the stage is a single video and the surrounding app draws
  # its own controls.
  if [ "$BROWSER_CHROME" = "kiosk" ]; then
    CHROME_MODE=(--start-fullscreen)
    log "browser chrome: kiosk (page only)"
  else
    CHROME_MODE=(--start-maximized)
    log "browser chrome: full (tab strip + address bar visible)"
  fi
  chromium "${COMMON[@]}" \
    --user-data-dir=/tmp/prof-target \
    --window-size="${SCREEN_W},${SCREEN_H}" \
    --window-position=0,0 \
    "${CHROME_MODE[@]}" \
    "$TARGET_URL" &
fi

sleep 3
# Hand input focus to the target so injected events reach the page. In tab mode
# the target is the first window; in screen mode it is the last one mapped.
TARGET_WIN=$(xdotool search --onlyvisible --class '[Cc]hromium' 2>/dev/null | tail -1 || true)
if [ -n "$TARGET_WIN" ]; then
  xdotool windowactivate --sync "$TARGET_WIN" 2>/dev/null || true
  xdotool windowfocus "$TARGET_WIN" 2>/dev/null || true
  log "focused target window $TARGET_WIN"
else
  log "WARN: no chromium window found to focus — input injection will not work"
fi

log "up. follow publisher diagnostics with: docker logs -f spike-remote-browser"
wait
