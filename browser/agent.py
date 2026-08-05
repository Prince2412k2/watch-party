#!/usr/bin/env python3
"""Control agent for the shared browser container.

Two listeners, deliberately split by trust boundary:

* ``0.0.0.0:AGENT_PORT`` — the control API. Only app/server, on the same docker
  network, is meant to reach it; every request needs the bearer token, and the
  agent refuses everything if no token is configured (fail closed, so a
  misconfigured deployment is inert rather than open).
* ``127.0.0.1:9000`` — the publisher page and its status callback. Loopback only.
  It has to be same-origin with the page so ``fetch('/state')`` from
  publisher.js is not a cross-origin request, and it must be http on localhost
  because getDisplayMedia/getUserMedia refuse to run outside a secure context
  (``file://`` does not count).

This is Python rather than Node because the image already needs python3 and
nothing else here does: it is ~300 lines of process supervision with no
dependencies, and adding a Node runtime to the image for it would cost more than
it saves. It owns three things and no policy:

1. Starting and stopping the two Chromium processes (publisher + target).
2. Destroying the profile between sessions.
3. Translating input events into xdotool.

Who may drive, which party owns the browser, and when to tear down are decided
by app/server. This agent trusts its caller precisely because the token gates it.
"""

import json
import os
import re
import shutil
import signal
import subprocess
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

AGENT_PORT = int(os.environ.get("AGENT_PORT", "8080"))
LOOPBACK_PORT = int(os.environ.get("LOOPBACK_PORT", "9000"))
AGENT_TOKEN = os.environ.get("BROWSER_AGENT_TOKEN", "")
DISPLAY = os.environ.get("DISPLAY", ":99")
SCREEN_W = int(os.environ.get("SCREEN_W", "1280"))
SCREEN_H = int(os.environ.get("SCREEN_H", "720"))
SCREEN_FPS = int(os.environ.get("SCREEN_FPS", "30"))
MAX_BITRATE_KBPS = int(os.environ.get("MAX_BITRATE_KBPS", "2500"))
PROFILE_ROOT = os.environ.get("PROFILE_ROOT", "/profiles")
PUBLISHER_ROOT = "/opt/browser/publisher"

# xdotool key syntax: optional modifiers then one keysym. Anything else is
# refused rather than passed through and hoped about — this is the one place
# where a string from a browser becomes an argument to a program. Four modifiers
# because there are four modifier keys; app/server's KEY_PATTERN must agree with
# this, or events pass there and vanish here.
KEY_RE = re.compile(r"^(?:(?:ctrl|alt|shift|super)\+){0,4}[A-Za-z0-9_]{1,20}$")
MAX_TEXT = 256
MAX_BATCH = 64
MAX_BODY = 16384

# Chromium flags shared by both windows.
#   --test-type suppresses the "unsupported command-line flag: --no-sandbox"
#     infobar, which otherwise sits across the top ~50px of the capture.
#   --use-fake-ui-for-media-stream auto-grants the capture permission prompt.
#   The backgrounding flags are hygiene for a permanently-occluded publisher
#     window; they were NOT the cause of the 15fps the spike chased (that was
#     livekit-client's screen-share preset — see publisher.js).
COMMON_FLAGS = [
    "--no-sandbox",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-search-engine-choice-screen",
    "--disable-features=Translate,MediaRouter,AcceptCHFrame",
    "--autoplay-policy=no-user-gesture-required",
    "--use-fake-ui-for-media-stream",
    "--test-type",
    "--disable-infobars",
    "--hide-scrollbars",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
    "--disable-background-timer-throttling",
]


def log(*parts):
    print("[agent]", *parts, flush=True)


def xdo(*args):
    env = dict(os.environ, DISPLAY=DISPLAY)
    return subprocess.run(
        ["xdotool", *args], env=env, capture_output=True, timeout=5, check=False
    )


def clamp(value, low, high):
    return max(low, min(high, int(value)))


class Session:
    """The one browser session this container can hold at a time.

    Guarded by a single lock. Every public method is safe to call from any
    handler thread, and every one of them is idempotent enough that a retry
    after a timeout does not corrupt state.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self.publisher = None      # subprocess.Popen
        self.target = None         # subprocess.Popen
        self.url = None
        self.started_at = None
        self.publishing = False
        self.last_error = None
        self.exited = None         # {"who": ..., "code": ...} once something dies
        self.stats = None

    # ── state ────────────────────────────────────────────────────────────────

    def status(self):
        with self._lock:
            return {
                "ok": True,
                "running": self.target is not None,
                "publishing": self.publishing,
                "url": self.url,
                "startedAt": self.started_at,
                "lastError": self.last_error,
                "exited": self.exited,
                "screen": {"w": SCREEN_W, "h": SCREEN_H},
                "stats": self.stats,
            }

    def note_publisher_event(self, event, message=None, stats=None):
        with self._lock:
            if event == "published":
                self.publishing = True
                self.last_error = None
            elif event == "fatal":
                self.publishing = False
                self.last_error = str(message)[:500] if message else "publisher failed"
            elif event == "stats" and isinstance(stats, dict):
                self.stats = stats

    # ── lifecycle ────────────────────────────────────────────────────────────

    def start(self, url, token, lk_url, kbps, fps):
        with self._lock:
            if self.target is not None and self.target.poll() is None:
                return False, "already running"

            # A previous session that crashed leaves processes behind; clearing
            # here (not only in stop) means a start can always succeed.
            self._kill_locked()
            self._wipe_profiles_locked()

            self.url = url
            self.started_at = int(time.time() * 1000)
            self.publishing = False
            self.last_error = None
            self.exited = None
            self.stats = None

            query = urllib.parse.urlencode({
                "lk": lk_url,
                "token": token,
                "kbps": kbps,
                "fps": fps,
                "w": SCREEN_W,
                "h": SCREEN_H,
            })
            publisher_url = f"http://127.0.0.1:{LOOPBACK_PORT}/publisher.html?{query}"

            # Order matters. The publisher starts FIRST and small so the target,
            # started second at full size, stacks above it — a whole-screen grab
            # then sees only the target. Reversing this publishes a stream with
            # the publisher's own diagnostics window in the corner of it.
            self.publisher = self._spawn([
                *COMMON_FLAGS,
                f"--user-data-dir={PROFILE_ROOT}/publisher",
                "--window-size=480,320",
                "--window-position=0,0",
                # No picker appears: the source is resolved from this flag.
                "--auto-select-desktop-capture-source=Entire screen",
                publisher_url,
            ])
            self.target = self._spawn([
                *COMMON_FLAGS,
                f"--user-data-dir={PROFILE_ROOT}/target",
                f"--window-size={SCREEN_W},{SCREEN_H}",
                "--window-position=0,0",
                # Maximized, not fullscreen: the party drives Chromium's own tab
                # strip and address bar, so they have to be in the capture.
                "--start-maximized",
                url,
            ])
            log(f"session started url={url}")
            return True, None

    def stop(self, reason="stop"):
        with self._lock:
            was_running = self.target is not None
            self._kill_locked()
            self._wipe_profiles_locked()
            self.url = None
            self.started_at = None
            self.publishing = False
            self.exited = None
            self.stats = None
            if was_running:
                log(f"session stopped ({reason})")
            return was_running

    def _spawn(self, args):
        env = dict(os.environ, DISPLAY=DISPLAY)
        return subprocess.Popen(
            ["chromium", *args],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            # Its own process group, so a kill takes the renderers and GPU
            # helpers with it rather than orphaning them onto the display.
            start_new_session=True,
        )

    def _kill_locked(self):
        for name in ("target", "publisher"):
            proc = getattr(self, name)
            setattr(self, name, None)
            if proc is None:
                continue
            try:
                os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                continue
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
        # Belt and braces: anything still holding a profile dir would survive the
        # wipe below and leak a signed-in session into the next party.
        subprocess.run(["pkill", "-9", "-f", f"--user-data-dir={PROFILE_ROOT}"],
                       capture_output=True, check=False)

    def _wipe_profiles_locked(self):
        """Destroy cookies, history, downloads and extensions.

        Best effort by design: PROFILE_ROOT is a tmpfs, so anything this fails to
        remove dies with the container anyway. A failure here must never block a
        stop, because a stop is on the path of a party ending.
        """
        for entry in ("publisher", "target"):
            path = os.path.join(PROFILE_ROOT, entry)
            try:
                shutil.rmtree(path)
            except FileNotFoundError:
                pass
            except OSError as exc:
                log(f"WARN: could not wipe {path}: {exc}")

    # ── watchdog ─────────────────────────────────────────────────────────────

    def reap(self):
        """Notice a browser that died on its own and record it.

        The party learns about a crash by polling /status, so the state has to be
        truthful without anyone having asked for a stop.
        """
        with self._lock:
            for name in ("target", "publisher"):
                proc = getattr(self, name)
                if proc is None:
                    continue
                code = proc.poll()
                if code is None:
                    continue
                log(f"{name} exited code={code}")
                self.exited = {"who": name, "code": code}
                self.publishing = False
                # One half dying makes the session useless: a dead target leaves
                # the publisher streaming an empty desktop, and a dead publisher
                # leaves a browser nobody can see.
                self._kill_locked()
                self._wipe_profiles_locked()
                self.url = None
                self.started_at = None
                return

    # ── input ────────────────────────────────────────────────────────────────

    def focus_target(self):
        """Hand input focus to the target window.

        Called before the first injected event of a session rather than at start:
        at start the window may not be mapped yet, and focusing nothing silently
        succeeds, leaving every later keystroke going nowhere.
        """
        result = xdo("search", "--onlyvisible", "--class", "[Cc]hromium")
        ids = [line for line in result.stdout.decode().split() if line.strip()]
        if not ids:
            return False
        # The target is the last window mapped (it started after the publisher).
        window = ids[-1]
        xdo("windowactivate", "--sync", window)
        xdo("windowfocus", window)
        return True

    def apply(self, events):
        with self._lock:
            live = self.target is not None and self.target.poll() is None
        if not live:
            return 0
        applied = 0
        for event in events[:MAX_BATCH]:
            if isinstance(event, dict) and inject(event):
                applied += 1
        return applied


def inject(event):
    kind = event.get("type")

    if kind in ("move", "down", "up", "click"):
        x = clamp(event.get("x", 0), 0, SCREEN_W - 1)
        y = clamp(event.get("y", 0), 0, SCREEN_H - 1)
        button = str(clamp(event.get("button", 1), 1, 5))
        xdo("mousemove", str(x), str(y))
        if kind == "down":
            xdo("mousedown", button)
        elif kind == "up":
            xdo("mouseup", button)
        elif kind == "click":
            xdo("click", button)
        return True

    if kind == "scroll":
        # xdotool has no scroll amount: buttons 4/5 are one notch each, so a
        # delta has to become N clicks. Capped because a trackpad fling arrives
        # as a huge deltaY and would otherwise fire hundreds of events.
        dy = event.get("dy", 0)
        button = "5" if dy > 0 else "4"
        for _ in range(clamp(abs(dy) / 100.0 + 0.5, 1, 5)):
            xdo("click", button)
        return True

    if kind == "key":
        combo = str(event.get("key", ""))
        if not KEY_RE.match(combo):
            return False
        xdo("key", "--clearmodifiers", combo)
        return True

    if kind == "text":
        text = str(event.get("text", ""))[:MAX_TEXT]
        if not text:
            return False
        # `--` so text starting with a dash is not read as an option.
        xdo("type", "--delay", "12", "--", text)
        return True

    return False


SESSION = Session()


def valid_target_url(value):
    if not isinstance(value, str) or len(value) > 2048:
        return False
    try:
        parsed = urllib.parse.urlparse(value)
    except ValueError:
        return False
    return parsed.scheme in ("http", "https") and bool(parsed.netloc)


class BaseHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass  # one line per mousemove would bury everything that matters

    def send_json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def read_json(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length <= 0:
            return {}
        if length > MAX_BODY:
            return None
        try:
            body = json.loads(self.rfile.read(length))
        except (ValueError, UnicodeDecodeError):
            return None
        return body if isinstance(body, dict) else None


class ControlHandler(BaseHandler):
    """The authenticated API app/server talks to."""

    def authorized(self):
        if not AGENT_TOKEN:
            return False
        header = self.headers.get("Authorization", "")
        return header == f"Bearer {AGENT_TOKEN}"

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        # Unauthenticated on purpose and deliberately stateless: this is the
        # container healthcheck, and it must not become a way to learn whether a
        # party is using the browser.
        if path == "/health":
            return self.send_json(200, {"ok": True})
        if not self.authorized():
            return self.send_json(401, {"error": "unauthorized"})
        if path == "/status":
            return self.send_json(200, SESSION.status())
        return self.send_json(404, {"error": "not found"})

    def do_POST(self):
        if not self.authorized():
            return self.send_json(401, {"error": "unauthorized"})
        path = self.path.split("?", 1)[0]
        body = self.read_json()
        if body is None:
            return self.send_json(400, {"error": "bad body"})

        if path == "/session/start":
            url = body.get("url")
            token = body.get("token")
            lk_url = body.get("lkUrl")
            if not valid_target_url(url):
                return self.send_json(400, {"error": "invalid url"})
            if not isinstance(token, str) or not token:
                return self.send_json(400, {"error": "missing token"})
            if not isinstance(lk_url, str) or not lk_url.startswith(("ws://", "wss://")):
                return self.send_json(400, {"error": "invalid lkUrl"})
            kbps = clamp(body.get("kbps", MAX_BITRATE_KBPS), 200, 8000)
            fps = clamp(body.get("fps", SCREEN_FPS), 5, 60)
            try:
                ok, error = SESSION.start(url, token, lk_url, kbps, fps)
            except OSError as exc:
                log(f"start failed: {exc}")
                return self.send_json(500, {"error": "start failed"})
            if not ok:
                return self.send_json(409, {"error": error})
            return self.send_json(200, {"ok": True})

        if path == "/session/stop":
            SESSION.stop(reason=str(body.get("reason", "stop"))[:40])
            return self.send_json(200, {"ok": True})

        if path == "/session/navigate":
            url = body.get("url")
            if not valid_target_url(url):
                return self.send_json(400, {"error": "invalid url"})
            # ctrl+l focuses the address bar; the delays let Chromium settle
            # between the three steps, which it needs when the page is busy.
            if not SESSION.focus_target():
                return self.send_json(409, {"error": "no window"})
            inject({"type": "key", "key": "ctrl+l"})
            time.sleep(0.09)
            inject({"type": "text", "text": url})
            time.sleep(0.13)
            inject({"type": "key", "key": "Return"})
            return self.send_json(200, {"ok": True})

        if path == "/input":
            events = body.get("events")
            if not isinstance(events, list):
                return self.send_json(400, {"error": "events must be a list"})
            if body.get("focus"):
                SESSION.focus_target()
            applied = SESSION.apply(events)
            return self.send_json(200, {"ok": True, "applied": applied})

        return self.send_json(404, {"error": "not found"})


class LoopbackHandler(BaseHandler):
    """Serves the publisher page and takes its status callbacks. Loopback only."""

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        # Relative paths are preserved, not flattened to a basename: the page
        # loads ./vendor/livekit-client.umd.js, and serving only basenames turned
        # that into a 404 — leaving window.LivekitClient undefined and the
        # publisher failing with "Cannot read properties of undefined".
        relative = path.lstrip("/") or "publisher.html"
        full = os.path.normpath(os.path.join(PUBLISHER_ROOT, relative))
        # Static files only, resolved under PUBLISHER_ROOT — no traversal out.
        if not full.startswith(PUBLISHER_ROOT + os.sep) or not os.path.isfile(full):
            return self.send_json(404, {"error": "not found"})
        ctype = ("text/html; charset=utf-8" if full.endswith(".html")
                 else "text/javascript" if full.endswith(".js")
                 else "application/octet-stream")
        with open(full, "rb") as handle:
            body = handle.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/state":
            return self.send_json(404, {"error": "not found"})
        body = self.read_json()
        if body is None:
            return self.send_json(400, {"error": "bad body"})
        SESSION.note_publisher_event(
            body.get("event"), body.get("message"), body.get("stats")
        )
        return self.send_json(200, {"ok": True})


def watchdog():
    while True:
        try:
            SESSION.reap()
        except Exception as exc:  # noqa: BLE001 — the watchdog must never die
            log(f"watchdog error: {exc}")
        time.sleep(1.0)


def main():
    if not AGENT_TOKEN:
        log("FATAL: BROWSER_AGENT_TOKEN is empty — refusing to start")
        raise SystemExit(1)

    loopback = ThreadingHTTPServer(("127.0.0.1", LOOPBACK_PORT), LoopbackHandler)
    threading.Thread(target=loopback.serve_forever, daemon=True).start()
    log(f"publisher served on 127.0.0.1:{LOOPBACK_PORT}")

    threading.Thread(target=watchdog, daemon=True).start()

    control = ThreadingHTTPServer(("0.0.0.0", AGENT_PORT), ControlHandler)
    log(f"control API on 0.0.0.0:{AGENT_PORT}")
    try:
        control.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        SESSION.stop(reason="shutdown")


if __name__ == "__main__":
    main()
