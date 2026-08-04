#!/usr/bin/env bash
# Driver for the remote-browser spike. See README.md for what each probe proves.
#
#   ./probe.sh build          vendor the livekit client + docker build
#   ./probe.sh token [room]   mint publisher/viewer tokens
#   ./probe.sh up [room]      mint, then start the container
#   ./probe.sh viewer         print the URL to watch it on (served by the container)
#   ./probe.sh stats [secs]   sample container CPU/memory
#   ./probe.sh goto <url>     navigate the remote browser
#   ./probe.sh newtab         open a new tab
#   ./probe.sh key <combo>    send a key combo (ctrl+w, F5, Tab, …)
#   ./probe.sh input          inject mouse+keyboard, prove it lands
#   ./probe.sh shot [out.png] screenshot the virtual display
#   ./probe.sh logs           follow publisher diagnostics
#   ./probe.sh down           stop and remove
set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT=$(cd ../.. && pwd)
CONTAINER=spike-remote-browser
COMPOSE=(docker compose -f compose.spike.yml)
VIEWER_PORT=${VIEWER_PORT:-8899}

die() { echo "error: $*" >&2; exit 1; }

vendor() {
  local src="$REPO_ROOT/app/client/node_modules/livekit-client/dist/livekit-client.umd.js"
  [ -f "$src" ] || die "livekit-client not installed. Run: (cd app/client && npm install)"
  mkdir -p publisher/vendor
  cp "$src" publisher/vendor/livekit-client.umd.js
  cp "$src" viewer/livekit-client.umd.js
  echo "vendored livekit-client.umd.js"
}

mint() {
  node mint-token.mjs "${1:-spike-remote-browser}"
}

case "${1:-}" in
  build)
    vendor
    "${COMPOSE[@]}" build
    ;;

  token)
    mint "${2:-}"
    ;;

  up)
    room=${2:-spike-remote-browser}
    vendor
    echo "minting tokens for room '$room'…"
    LIVEKIT_TOKEN=$(node mint-token.mjs "$room" --publisher-only) || die "token minting failed"
    VIEWER_TOKEN=$(node mint-token.mjs "$room" --viewer-only) || die "token minting failed"
    export LIVEKIT_TOKEN VIEWER_TOKEN VIEWER_PORT
    "${COMPOSE[@]}" up -d --build
    echo
    echo "  WATCH IT:  http://localhost:$VIEWER_PORT"
    echo
    echo "next:"
    echo "  ./probe.sh logs            # watch it connect and publish"
    echo "  ./probe.sh stats 60        # measure what it costs"
    ;;

  viewer)
    # The container serves and publishes the page itself; nothing to start here.
    echo "  WATCH IT:  http://localhost:$VIEWER_PORT"
    docker port "$CONTAINER" 2>/dev/null | sed 's/^/  published: /' || die "container not running — ./probe.sh up"
    ;;

  stats)
    secs=${2:-60}
    echo "sampling $CONTAINER for ${secs}s (1 sample/sec)…"
    tmp=$(mktemp)
    for _ in $(seq 1 "$secs"); do
      docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}}' "$CONTAINER" 2>/dev/null \
        | tr -d '%' >> "$tmp" || true
      sleep 1
    done
    echo
    awk '{ c=$1; s+=c; n++; if (c>mx) mx=c }
         END { if (n) printf "CPU  avg %.1f%%  peak %.1f%%  (n=%d, %% of ONE core)\n", s/n, mx, n
               else print "no samples — is the container running?" }' "$tmp"
    echo "memory (last sample): $(tail -1 "$tmp" | cut -d' ' -f2-)"
    echo
    echo "Divide CPU by 100 for core-equivalents: 380% = 3.8 cores."
    rm -f "$tmp"
    ;;

  goto)
    url=${2:?usage: ./probe.sh goto <url>}
    # Focus the target window explicitly: without a focused window the WM has
    # nowhere to deliver keystrokes and the typing silently goes nowhere.
    win=$(docker exec -e DISPLAY=:99 "$CONTAINER" \
      xdotool search --onlyvisible --class '[Cc]hromium' 2>/dev/null | tail -1)
    [ -n "$win" ] || die "no chromium window found — is it up? ./probe.sh logs"
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool windowactivate --sync "$win"
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool key --clearmodifiers ctrl+l
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool type --delay 25 "$url"
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool key --clearmodifiers Return
    echo "navigated to $url — watch it change at http://localhost:$VIEWER_PORT"
    ;;

  newtab)
    win=$(docker exec -e DISPLAY=:99 "$CONTAINER" \
      xdotool search --onlyvisible --class '[Cc]hromium' 2>/dev/null | tail -1)
    [ -n "$win" ] || die "no chromium window found"
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool windowactivate --sync "$win"
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool key --clearmodifiers ctrl+t
    echo "opened a new tab"
    ;;

  key)
    combo=${2:?usage: ./probe.sh key <xdotool-key>   e.g. ctrl+w, F5, Tab}
    win=$(docker exec -e DISPLAY=:99 "$CONTAINER" \
      xdotool search --onlyvisible --class '[Cc]hromium' 2>/dev/null | tail -1)
    [ -n "$win" ] || die "no chromium window found"
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool windowactivate --sync "$win"
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool key --clearmodifiers "$combo"
    echo "sent $combo"
    ;;

  input)
    echo "injecting input into the container's display…"
    # Deliberately crude: this only has to prove the path works. The real
    # feature would relay normalized events over the existing Socket.IO and the
    # control lease in app/server/neko/lease.js.
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool mousemove 640 360 || die "mousemove failed"
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool click 1 || die "click failed"
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool key --clearmodifiers ctrl+l || true
    docker exec -e DISPLAY=:99 "$CONTAINER" xdotool type --delay 40 "example.com" || true
    echo "injected: mousemove 640,360 + click + ctrl+l + typed 'example.com'"
    echo "Now check the viewer: did the pointer move, and did the text appear?"
    echo "Time the gap between this command returning and the change showing —"
    echo "that gap is your input latency."
    ;;

  shot)
    out=${2:-shot.png}
    docker exec -e DISPLAY=:99 "$CONTAINER" \
      bash -c 'xwd -root -silent | xwdtopnm 2>/dev/null | pnmtopng 2>/dev/null' > "$out" \
      || die "screenshot failed"
    [ -s "$out" ] || die "screenshot came out empty — is Xvfb up? check ./probe.sh logs"
    echo "wrote $out ($(wc -c < "$out") bytes)"
    ;;

  logs)
    docker logs -f "$CONTAINER" 2>&1 | grep --line-buffered -E '\[publisher\]|\[entrypoint\]|FATAL|ERROR' || true
    ;;

  down)
    "${COMPOSE[@]}" down -v --remove-orphans
    ;;

  *)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
