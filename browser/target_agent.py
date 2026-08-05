#!/usr/bin/env python3

import json
import os
import shutil
import signal
import subprocess
import threading
import time
import urllib.parse
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TARGET_PORT = int(os.environ.get("TARGET_AGENT_PORT", "8081"))
AGENT_TOKEN = os.environ.get("BROWSER_TARGET_TOKEN", "")
DISPLAY = os.environ.get("DISPLAY", ":99")
SCREEN_W = int(os.environ.get("SCREEN_W", "1280"))
SCREEN_H = int(os.environ.get("SCREEN_H", "720"))
STATE_ROOT = os.environ.get("TARGET_STATE_ROOT", "/target-state")
PROXY_URL = os.environ.get("TARGET_PROXY_URL", "http://browser-egress-proxy:8888")
NETWORK_MODE = os.environ.get("BROWSER_NETWORK_MODE", "")
EXTRA_CA_ROOT = "/opt/browser/extra-ca"

with open(os.path.join(os.path.dirname(__file__), "policy.json"), encoding="utf-8") as handle:
    POLICY = json.load(handle)


def initialize_storage(root=STATE_ROOT):
    os.makedirs(root, mode=0o700, exist_ok=True)
    for entry in os.listdir(root):
        path = os.path.join(root, entry)
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.unlink(path)


class TargetSession:
    def __init__(self):
        self._lock = threading.Lock()
        self.process = None
        self.generation = None
        self.url = None
        self.started_at = None
        self.last_error = None
        self._cancelled = set()
        self._cancelled_order = deque()

    def status(self):
        with self._lock:
            running = self.process is not None and self.process.poll() is None
            return {
                "ok": True,
                "running": running,
                "generation": self.generation,
                "url": self.url,
                "startedAt": self.started_at,
                "lastError": self.last_error,
            }

    def start(self, url, generation):
        with self._lock:
            if generation in self._cancelled:
                return False, "stale generation"
            if self.process is not None and self.process.poll() is None:
                return False, "already running"
            if not self._kill_locked():
                return False, "cleanup pending"
            self._wipe_locked()
            state = self._prepare_state_locked()
            env = {
                "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
                "LANG": os.environ.get("LANG", "C.UTF-8"),
                "DISPLAY": DISPLAY,
                "XAUTHORITY": os.environ.get("XAUTHORITY", "/xauth/target"),
                "PULSE_SERVER": os.environ.get("PULSE_SERVER", "unix:/pulse/native"),
                "PULSE_COOKIE": os.environ.get("PULSE_COOKIE", "/pulse/cookie"),
                "HOME": os.path.join(state, "home"),
                "XDG_RUNTIME_DIR": os.path.join(state, "runtime"),
                "XDG_CACHE_HOME": os.path.join(state, "cache"),
                "XDG_CONFIG_HOME": os.path.join(state, "home", ".config"),
                "XDG_DATA_HOME": os.path.join(state, "home", ".local", "share"),
                "TMPDIR": os.path.join(state, "tmp"),
            }
            args = [
                "chromium",
                "--no-first-run",
                "--no-default-browser-check",
                "--disable-search-engine-choice-screen",
                "--disable-features=Translate,MediaRouter,AcceptCHFrame",
                "--autoplay-policy=no-user-gesture-required",
                "--disable-infobars",
                "--disable-setuid-sandbox",
                "--disable-quic",
                "--hide-scrollbars",
                "--disable-backgrounding-occluded-windows",
                "--disable-renderer-backgrounding",
                "--disable-background-timer-throttling",
                f"--user-data-dir={state}/profile",
                f"--disk-cache-dir={state}/cache",
                f"--download-default-directory={state}/downloads",
                f"--proxy-server={PROXY_URL}",
                "--proxy-bypass-list=<-loopback>",
                "--force-webrtc-ip-handling-policy=disable_non_proxied_udp",
                f"--window-size={SCREEN_W},{SCREEN_H}",
                "--window-position=0,0",
                "--start-maximized",
                url,
            ]
            try:
                self.process = subprocess.Popen(
                    args, env=env, stdout=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except OSError:
                self._wipe_locked()
                raise
            self.generation = generation
            self.url = url
            self.started_at = int(time.time() * 1000)
            self.last_error = None
            return True, None

    def stop(self, generation=None):
        with self._lock:
            if generation and self.generation not in (None, generation):
                return False, "generation mismatch", False
            if generation:
                self._cancel_generation_locked(generation)
            was_running = self.process is not None
            if not self._kill_locked():
                self.last_error = "target cleanup failed"
                return False, "cleanup failed", was_running
            try:
                self._wipe_locked()
            except OSError:
                self.last_error = "target state cleanup failed"
                return False, "cleanup failed", was_running
            self.generation = None
            self.url = None
            self.started_at = None
            self.last_error = None
            return True, None, was_running

    def reap(self):
        with self._lock:
            if self.process is None or self.process.poll() is None:
                return
            self.last_error = f"target exited with code {self.process.returncode}"
            self.process = None
            self._wipe_locked()
            self.generation = None
            self.url = None
            self.started_at = None

    def _prepare_state_locked(self):
        state = os.path.join(STATE_ROOT, "session")
        for entry in ("profile", "cache", "downloads", "home", "tmp", "runtime"):
            os.makedirs(os.path.join(state, entry), mode=0o700, exist_ok=True)
        nssdb = os.path.join(state, "home", ".pki", "nssdb")
        os.makedirs(nssdb, mode=0o700, exist_ok=True)
        subprocess.run(
            ["certutil", "-d", f"sql:{nssdb}", "-N", "--empty-password"],
            capture_output=True, check=False,
        )
        if os.path.isdir(EXTRA_CA_ROOT):
            for cert in os.listdir(EXTRA_CA_ROOT):
                if cert.endswith(".crt"):
                    subprocess.run([
                        "certutil", "-d", f"sql:{nssdb}", "-A", "-t", "C,,",
                        "-n", cert, "-i", os.path.join(EXTRA_CA_ROOT, cert),
                    ], capture_output=True, check=False)
        return state

    def _kill_locked(self):
        process = self.process
        if process is None:
            return True
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except (ProcessLookupError, PermissionError):
                return False
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                return False
        self.process = None
        return True

    def _wipe_locked(self):
        path = os.path.join(STATE_ROOT, "session")
        try:
            shutil.rmtree(path)
        except FileNotFoundError:
            pass

    def _cancel_generation_locked(self, generation):
        if generation in self._cancelled:
            return
        self._cancelled.add(generation)
        self._cancelled_order.append(generation)
        while len(self._cancelled_order) > 256:
            self._cancelled.discard(self._cancelled_order.popleft())


SESSION = TargetSession()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def authorized(self):
        return bool(AGENT_TOKEN) and self.headers.get("Authorization") == f"Bearer {AGENT_TOKEN}"

    def json(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def body(self):
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length <= 0 or length > POLICY["maxBody"]:
            return None
        try:
            value = json.loads(self.rfile.read(length))
        except (ValueError, UnicodeDecodeError):
            return None
        return value if isinstance(value, dict) else None

    def do_GET(self):
        if self.path == "/health":
            return self.json(200, {"ok": True})
        if not self.authorized():
            return self.json(401, {"error": "unauthorized"})
        if self.path == "/status":
            return self.json(200, SESSION.status())
        return self.json(404, {"error": "not found"})

    def do_POST(self):
        if not self.authorized():
            return self.json(401, {"error": "unauthorized"})
        body = self.body()
        if body is None:
            return self.json(400, {"error": "bad body"})
        generation = body.get("generation")
        if generation is not None and (not isinstance(generation, str) or not generation or len(generation) > 128):
            return self.json(400, {"error": "invalid generation"})
        if self.path == "/start":
            url = body.get("url")
            try:
                parsed = urllib.parse.urlparse(url) if isinstance(url, str) else None
            except ValueError:
                parsed = None
            if (
                not parsed or parsed.scheme not in ("http", "https") or not parsed.hostname
                or parsed.username is not None or parsed.password is not None
                or len(url) > POLICY["maxUrlLength"] or not generation
            ):
                return self.json(400, {"error": "invalid start"})
            try:
                ok, error = SESSION.start(url, generation)
            except OSError:
                return self.json(500, {"error": "start failed"})
            return self.json(200 if ok else 409, {"ok": ok, **({"error": error} if error else {})})
        if self.path == "/stop":
            ok, error, stopped = SESSION.stop(generation)
            if not ok:
                return self.json(409 if error == "generation mismatch" else 503, {"error": error})
            return self.json(200, {"ok": True, "stopped": stopped})
        return self.json(404, {"error": "not found"})


def watchdog():
    while True:
        SESSION.reap()
        time.sleep(1)


def main():
    if not AGENT_TOKEN or NETWORK_MODE != "isolated-sidecars-v1":
        raise SystemExit(1)
    initialize_storage()
    threading.Thread(target=watchdog, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", TARGET_PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
