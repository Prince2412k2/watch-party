#!/usr/bin/env python3
"""Serves the viewer page and injects its input into the X display.

Runs inside the spike container. Replaces `python3 -m http.server`, which could
only serve static files and so gave us a stream you could watch but not touch.

POST /input takes a JSON event and turns it into xdotool. Two things matter here:

* No shell. Every xdotool call goes through subprocess with an argv list, and key
  names are whitelisted by regex, because this endpoint is published on 0.0.0.0
  and its body is attacker-controlled the moment anyone else can reach the port.
* Coordinates arrive already in screen space. The viewer does the letterbox
  correction, since only it knows how the video is laid out.
"""

import json
import os
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.environ.get("VIEWER_ROOT", "/opt/spike/viewerroot")
DISPLAY = os.environ.get("DISPLAY", ":99")
PORT = int(os.environ.get("VIEWER_LISTEN_PORT", "8899"))
SCREEN_W = int(os.environ.get("SCREEN_W", "1280"))
SCREEN_H = int(os.environ.get("SCREEN_H", "720"))

# xdotool key syntax: optional modifiers then one keysym. Anything else is refused
# rather than passed through and hoped about.
KEY_RE = re.compile(r"^(?:(?:ctrl|alt|shift|super)\+){0,3}[A-Za-z0-9_]{1,20}$")
MAX_TEXT = 256
MAX_BATCH = 64  # matches the viewer's queue cap; bounds work per request


def xdo(*args):
    env = dict(os.environ, DISPLAY=DISPLAY)
    return subprocess.run(
        ["xdotool", *args], env=env, capture_output=True, timeout=5, check=False
    )


def clamp(v, lo, hi):
    return max(lo, min(hi, int(v)))


def handle(ev):
    kind = ev.get("type")

    if kind in ("move", "down", "up", "click"):
        x = clamp(ev.get("x", 0), 0, SCREEN_W - 1)
        y = clamp(ev.get("y", 0), 0, SCREEN_H - 1)
        btn = str(clamp(ev.get("button", 1), 1, 5))
        xdo("mousemove", str(x), str(y))
        if kind == "down":
            xdo("mousedown", btn)
        elif kind == "up":
            xdo("mouseup", btn)
        elif kind == "click":
            xdo("click", btn)
        return True

    if kind == "scroll":
        # xdotool has no scroll amount: buttons 4/5 are one notch each, so a
        # delta has to become N clicks. Capped because a trackpad fling arrives
        # as a huge deltaY and would otherwise fire hundreds of events.
        dy = ev.get("dy", 0)
        btn = "5" if dy > 0 else "4"
        notches = clamp(abs(dy) / 100.0 + 0.5, 1, 5)
        for _ in range(notches):
            xdo("click", btn)
        return True

    if kind == "key":
        combo = str(ev.get("key", ""))
        if not KEY_RE.match(combo):
            return False
        xdo("key", "--clearmodifiers", combo)
        return True

    if kind == "text":
        text = str(ev.get("text", ""))[:MAX_TEXT]
        if not text:
            return False
        # `--` so text starting with a dash is not read as an option.
        xdo("type", "--delay", "12", "--", text)
        return True

    return False


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass  # one line per mousemove would bury the publisher's diagnostics

    def _send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_POST(self):
        if self.path != "/input":
            return self._send(404, b"not found")
        try:
            n = int(self.headers.get("Content-Length", "0"))
            if n <= 0 or n > 8192:
                return self._send(400, b"bad length")
            body = json.loads(self.rfile.read(n))
            if not isinstance(body, dict):
                return self._send(400, b"rejected")
            # The viewer batches so it can keep exactly one request in flight.
            # A bare single event is still accepted — curl and probe.sh use it.
            events = body.get("events")
            if isinstance(events, list):
                ok = False
                for ev in events[:MAX_BATCH]:
                    if isinstance(ev, dict) and handle(ev):
                        ok = True
            else:
                ok = handle(body)
            return self._send(200 if ok else 400, b"ok" if ok else b"rejected")
        except Exception as exc:  # noqa: BLE001 - a bad event must not kill the server
            return self._send(500, str(exc).encode()[:200])

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        name = "index.html" if path in ("/", "/index.html") else os.path.basename(path)
        full = os.path.join(ROOT, name)
        if not os.path.isfile(full):
            return self._send(404, b"not found")
        ctype = "text/html; charset=utf-8" if name.endswith(".html") else \
                "text/javascript" if name.endswith(".js") else "application/octet-stream"
        with open(full, "rb") as fh:
            self._send(200, fh.read(), ctype)


if __name__ == "__main__":
    print(f"[viewer-server] serving {ROOT} on 0.0.0.0:{PORT}, injecting into {DISPLAY}",
          flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
