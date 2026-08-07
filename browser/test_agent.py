import socket
import threading
import tempfile
import unittest
from io import BytesIO
from pathlib import Path
from unittest.mock import patch

import agent
import network
import target_agent


def address(ip):
    family = socket.AF_INET6 if ":" in ip else socket.AF_INET
    sockaddr = (ip, 443, 0, 0) if family == socket.AF_INET6 else (ip, 443)
    return family, socket.SOCK_STREAM, socket.IPPROTO_TCP, "", sockaddr


class FakeProcess:
    def poll(self):
        return None


class CapturingSocket:
    def __init__(self):
        self.payload = bytearray()

    def sendall(self, chunk):
        self.payload.extend(chunk)


class FakeSession(agent.Session):
    def __init__(self, spawn_entered=None, release_spawn=None):
        super().__init__()
        self.spawn_entered = spawn_entered
        self.release_spawn = release_spawn
        self.spawn_count = 0

    def _spawn(self, args, state_root):
        self.spawn_count += 1
        if self.spawn_count == 1 and self.spawn_entered:
            self.spawn_entered.set()
            self.release_spawn.wait(timeout=2)
        return FakeProcess()

    def _prepare_state_locked(self, name):
        return f"/tmp/{name}"

    def _kill_locked(self):
        self.target = None
        self.publisher = None
        return True

    def _wipe_profiles_locked(self):
        return True


class UrlPolicyTests(unittest.TestCase):
    def test_accepts_only_when_every_dns_answer_is_public(self):
        with patch.object(network.socket, "getaddrinfo", return_value=[address("93.184.216.34")]):
            self.assertEqual(len(network.resolve_public("example.com", 443)), 1)

        with patch.object(network.socket, "getaddrinfo", return_value=[
            address("93.184.216.34"), address("127.0.0.1")
        ]):
            with self.assertRaises(ValueError):
                network.resolve_public("example.com", 443)

        with patch.object(network.socket, "getaddrinfo", return_value=[address("2606:4700:4700::1111")]):
            self.assertEqual(len(network.resolve_public("example.com", 443)), 1)

    def test_rejects_internal_names_and_address_ranges(self):
        for url in (
            "http://localhost", "http://livekit:7880", "http://service.internal",
            "http://127.0.0.1", "http://169.254.169.254", "http://10.0.0.1",
            "http://[::1]", "http://[fe80::1]",
        ):
            self.assertFalse(agent.valid_target_url(url), url)

    def test_rejects_nat64_private_and_deployment_denied_public_addresses(self):
        self.assertTrue(network.is_denied_address("64:ff9b::a00:1"))
        denied = network.parse_denied_networks("93.184.216.34,2606:4700::/32")
        self.assertTrue(network.is_denied_address("93.184.216.34", denied))
        self.assertTrue(network.is_denied_address("2606:4700:4700::1111", denied))


def target_response(method, path, body=None, timeout=15):
    if path == "/status":
        return {"ok": True, "body": {"running": True, "generation": "lease-1"}}
    if path == "/stop":
        return {"ok": True, "body": {"stopped": True}}
    return {"ok": True, "body": {"ok": True}}


class LifecycleTests(unittest.TestCase):
    def test_status_requires_both_browser_processes(self):
        session = agent.Session()
        session.publisher = FakeProcess()
        session.generation = "lease-1"
        with patch.object(agent, "target_call", side_effect=target_response):
            status = session.status()
        self.assertTrue(status["running"])
        self.assertTrue(status["publisherRunning"])
        self.assertTrue(status["targetRunning"])

        session.publisher = None
        with patch.object(agent, "target_call", side_effect=target_response):
            status = session.status()
        self.assertFalse(status["running"])
        self.assertFalse(status["publisherRunning"])
        self.assertTrue(status["targetRunning"])

    def test_teardown_serializes_behind_delayed_start_and_removes_processes(self):
        spawn_entered = threading.Event()
        release_spawn = threading.Event()
        session = FakeSession(spawn_entered, release_spawn)
        started = []
        stopped = []

        with patch.object(agent, "target_call", side_effect=target_response):
            start_thread = threading.Thread(target=lambda: started.append(session.start(
                "https://example.com", "token", "ws://livekit:7880", 2500, 30, "lease-1"
            )))
            start_thread.start()
            self.assertTrue(spawn_entered.wait(timeout=1))

            stop_thread = threading.Thread(target=lambda: stopped.append(session.stop("teardown", "lease-1")))
            stop_thread.start()
            release_spawn.set()
            start_thread.join(timeout=2)
            stop_thread.join(timeout=2)

        self.assertEqual(started, [(True, None)])
        self.assertEqual(stopped, [(True, None, True)])
        self.assertIsNone(session.publisher)
        self.assertIsNone(session.generation)

    def test_start_arriving_after_teardown_is_rejected(self):
        session = FakeSession()
        with patch.object(agent, "target_call", side_effect=target_response):
            self.assertEqual(session.stop("teardown", "lease-2"), (True, None, True))
            self.assertEqual(session.start(
                "https://example.com", "token", "ws://livekit:7880", 2500, 30, "lease-2"
            ), (False, "stale generation"))
        self.assertEqual(session.spawn_count, 0)

    def test_generation_mismatch_is_a_conflict_and_preserves_session(self):
        session = FakeSession()
        session.generation = "new"
        with patch.object(agent, "target_call", side_effect=target_response) as target:
            self.assertEqual(session.stop("stale", "old"), (False, "generation mismatch", False))
        target.assert_not_called()
        self.assertEqual(session.generation, "new")


class StorageTests(unittest.TestCase):
    def test_agent_restart_removes_all_previous_writable_state(self):
        with tempfile.TemporaryDirectory() as root:
            stale = Path(root, "publisher", "downloads", "secret.txt")
            stale.parent.mkdir(parents=True)
            stale.write_text("secret")
            Path(root, "orphan.tmp").write_text("orphan")
            agent.initialize_storage(root)
            self.assertEqual(list(Path(root).iterdir()), [])

    def test_target_restart_removes_downloads_and_profile_state(self):
        with tempfile.TemporaryDirectory() as root:
            stale = Path(root, "session", "profile", "Cookies")
            download = Path(root, "session", "downloads", "file.bin")
            stale.parent.mkdir(parents=True)
            download.parent.mkdir(parents=True)
            stale.write_text("cookie")
            download.write_bytes(b"download")
            target_agent.initialize_storage(root)
            self.assertEqual(list(Path(root).iterdir()), [])


class ProxyLimitTests(unittest.TestCase):
    def test_plain_http_content_length_body_is_forwarded_from_buffered_input(self):
        proxy = object.__new__(network.EgressProxy)
        proxy.rfile = BytesIO(b"browser request body")
        upstream = CapturingSocket()
        proxy.forward_request_body([("Content-Length", "20")], upstream)
        self.assertEqual(bytes(upstream.payload), b"browser request body")

    def test_plain_http_chunked_body_is_forwarded_from_buffered_input(self):
        proxy = object.__new__(network.EgressProxy)
        proxy.rfile = BytesIO(b"5\r\nhello\r\n0\r\nX-Trace: done\r\n\r\n")
        upstream = CapturingSocket()
        proxy.forward_request_body([("Transfer-Encoding", "chunked")], upstream)
        self.assertEqual(bytes(upstream.payload), b"5\r\nhello\r\n0\r\nX-Trace: done\r\n\r\n")

    def test_server_refuses_connections_above_its_thread_bound(self):
        entered = threading.Event()
        release = threading.Event()

        class SlowHandler(network.socketserver.BaseRequestHandler):
            def handle(self):
                entered.set()
                release.wait(timeout=2)

        with patch.object(network, "MAX_CONNECTIONS", 1):
            server = network.ThreadingTCPServer(("127.0.0.1", 0), SlowHandler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        first = socket.create_connection(server.server_address)
        self.assertTrue(entered.wait(timeout=1))
        second = socket.create_connection(server.server_address)
        second.settimeout(1)
        self.assertEqual(second.recv(1), b"")
        release.set()
        first.close()
        second.close()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
