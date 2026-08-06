#!/usr/bin/env python3

import argparse
import ipaddress
import os
import select
import socket
import socketserver
import threading
import time
import urllib.parse

MAX_CONNECTIONS = int(os.environ.get("PROXY_MAX_CONNECTIONS", "64"))
HEADER_TIMEOUT = int(os.environ.get("PROXY_HEADER_TIMEOUT_SECONDS", "10"))
IDLE_TIMEOUT = int(os.environ.get("PROXY_IDLE_TIMEOUT_SECONDS", "30"))
MAX_TUNNEL_SECONDS = int(os.environ.get("PROXY_MAX_TUNNEL_SECONDS", "600"))
MAX_HEADERS = 16384


def parse_denied_networks(value):
    networks = []
    for raw in value.split(","):
        candidate = raw.strip()
        if not candidate:
            continue
        try:
            networks.append(ipaddress.ip_network(candidate, strict=False))
        except ValueError as exc:
            raise ValueError(f"invalid denied address or CIDR: {candidate}") from exc
    return tuple(networks)


DENIED_NETWORKS = parse_denied_networks(",".join(filter(None, (
    os.environ.get("BROWSER_DENY_ADDRESSES", ""),
    os.environ.get("VPS_PUBLIC_IP", ""),
))))
NAT64_WELL_KNOWN = ipaddress.ip_network("64:ff9b::/96")


def embedded_ipv4(address):
    if isinstance(address, ipaddress.IPv4Address):
        return address
    if address.ipv4_mapped:
        return address.ipv4_mapped
    if address in NAT64_WELL_KNOWN:
        return ipaddress.IPv4Address(address.packed[-4:])
    return None


def is_denied_address(value, denied_networks=None):
    address = ipaddress.ip_address(value)
    networks = DENIED_NETWORKS if denied_networks is None else denied_networks
    if not address.is_global or any(address in network for network in networks):
        return True
    translated = embedded_ipv4(address)
    return translated is not None and (
        not translated.is_global or any(translated in network for network in networks)
    )


def blocked_hostname(hostname):
    lowered = hostname.rstrip(".").lower()
    return "." not in lowered or lowered == "localhost" or lowered.endswith((
        ".localhost", ".local", ".internal", ".home.arpa", ".test", ".invalid"
    ))


def resolve_public(hostname, port):
    try:
        literal = ipaddress.ip_address(hostname)
    except ValueError:
        if blocked_hostname(hostname):
            raise ValueError("internal hostname")
        addresses = socket.getaddrinfo(hostname, port, type=socket.SOCK_STREAM)
    else:
        addresses = socket.getaddrinfo(str(literal), port, type=socket.SOCK_STREAM)
    if not addresses:
        raise ValueError("unresolved hostname")
    if any(is_denied_address(entry[4][0]) for entry in addresses):
        raise ValueError("denied address")
    return addresses


def connect_public(hostname, port):
    last_error = None
    for family, socktype, proto, _, address in resolve_public(hostname, port):
        upstream = socket.socket(family, socktype, proto)
        upstream.settimeout(10)
        try:
            upstream.connect(address)
            upstream.settimeout(None)
            return upstream
        except OSError as exc:
            last_error = exc
            upstream.close()
    raise last_error or OSError("could not connect")


def relay(left, right):
    started = time.monotonic()
    while time.monotonic() - started < MAX_TUNNEL_SECONDS:
        readable, _, _ = select.select((left, right), (), (), IDLE_TIMEOUT)
        if not readable:
            return
        for source in readable:
            chunk = source.recv(65536)
            if not chunk:
                return
            destination = right if source is left else left
            destination.sendall(chunk)


class BoundedThreadingMixIn(socketserver.ThreadingMixIn):
    daemon_threads = True

    def __init__(self, *args, **kwargs):
        self._slots = threading.BoundedSemaphore(MAX_CONNECTIONS)
        super().__init__(*args, **kwargs)

    def process_request(self, request, client_address):
        if not self._slots.acquire(blocking=False):
            request.close()
            return
        super().process_request(request, client_address)

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._slots.release()


class ThreadingTCPServer(BoundedThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True


class EgressProxy(socketserver.StreamRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(HEADER_TIMEOUT)

    def handle(self):
        request_line = self.rfile.readline(65537)
        if not request_line or len(request_line) > 65536:
            return self.reject(400)
        try:
            method, target, version = request_line.decode("iso-8859-1").strip().split(" ", 2)
            headers = self.read_headers()
            if method.upper() == "CONNECT":
                host, port = self.parse_authority(target)
                upstream = connect_public(host, port)
                self.wfile.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            else:
                parsed = urllib.parse.urlsplit(target)
                if parsed.scheme != "http" or not parsed.hostname:
                    return self.reject(400)
                upstream = connect_public(parsed.hostname, parsed.port or 80)
                origin = urllib.parse.urlunsplit(("", "", parsed.path or "/", parsed.query, ""))
                upstream.sendall(f"{method} {origin} {version}\r\n".encode("iso-8859-1"))
                for name, value in headers:
                    if name.lower() not in ("proxy-authorization", "proxy-connection"):
                        upstream.sendall(f"{name}: {value}\r\n".encode("iso-8859-1"))
                upstream.sendall(b"\r\n")
                self.forward_request_body(headers, upstream)
        except (OSError, UnicodeError, ValueError):
            return self.reject(403)
        self.connection.settimeout(None)
        try:
            relay(self.connection, upstream)
        finally:
            upstream.close()

    def read_headers(self):
        headers = []
        total = 0
        while True:
            line = self.rfile.readline(8193)
            total += len(line)
            if not line or line in (b"\r\n", b"\n"):
                return headers
            if len(line) > 8192 or total > MAX_HEADERS:
                raise ValueError("headers too large")
            name, separator, value = line.decode("iso-8859-1").partition(":")
            if not separator or "\r" in name or "\n" in name:
                raise ValueError("bad header")
            headers.append((name.strip(), value.strip()))

    def forward_request_body(self, headers, upstream):
        content_lengths = [value for name, value in headers if name.lower() == "content-length"]
        transfer_encodings = [value.lower() for name, value in headers if name.lower() == "transfer-encoding"]
        if content_lengths and transfer_encodings:
            raise ValueError("ambiguous request body")
        if transfer_encodings:
            if transfer_encodings != ["chunked"]:
                raise ValueError("unsupported transfer encoding")
            return self.forward_chunked_body(upstream)
        if not content_lengths:
            return
        if len(set(content_lengths)) != 1:
            raise ValueError("conflicting content length")
        remaining = int(content_lengths[0])
        if remaining < 0:
            raise ValueError("invalid content length")
        while remaining:
            chunk = self.rfile.read(min(remaining, 65536))
            if not chunk:
                raise ValueError("truncated request body")
            upstream.sendall(chunk)
            remaining -= len(chunk)

    def forward_chunked_body(self, upstream):
        while True:
            line = self.rfile.readline(8193)
            if not line or len(line) > 8192 or not line.endswith(b"\n"):
                raise ValueError("invalid chunk")
            try:
                size = int(line.split(b";", 1)[0].strip(), 16)
            except ValueError as exc:
                raise ValueError("invalid chunk size") from exc
            upstream.sendall(line)
            if size == 0:
                while True:
                    trailer = self.rfile.readline(8193)
                    if not trailer or len(trailer) > 8192:
                        raise ValueError("invalid trailer")
                    upstream.sendall(trailer)
                    if trailer in (b"\r\n", b"\n"):
                        return
            payload = self.rfile.read(size + 2)
            if len(payload) != size + 2 or not payload.endswith(b"\r\n"):
                raise ValueError("truncated chunk")
            upstream.sendall(payload)

    @staticmethod
    def parse_authority(authority):
        parsed = urllib.parse.urlsplit(f"//{authority}")
        if not parsed.hostname or parsed.username is not None or parsed.password is not None:
            raise ValueError("bad authority")
        return parsed.hostname, parsed.port or 443

    def reject(self, status):
        reason = "Forbidden" if status == 403 else "Bad Request"
        self.wfile.write(
            f"HTTP/1.1 {status} {reason}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".encode()
        )


class FixedGateway(socketserver.BaseRequestHandler):
    target = None

    def handle(self):
        upstream = socket.create_connection(self.target, timeout=10)
        try:
            relay(self.request, upstream)
        finally:
            upstream.close()


def run_proxy(port):
    with ThreadingTCPServer(("0.0.0.0", port), EgressProxy) as server:
        server.serve_forever()


def run_gateways(mappings):
    servers = []
    for listen_port, host, target_port in mappings:
        handler = type(f"Gateway{listen_port}", (FixedGateway,), {"target": (host, target_port)})
        server = ThreadingTCPServer(("0.0.0.0", listen_port), handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        servers.append(server)
    try:
        threading.Event().wait()
    finally:
        for server in servers:
            server.shutdown()


def parse_mapping(value):
    listen_port, host, target_port = value.split(":", 2)
    return int(listen_port), host, int(target_port)


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    proxy = subparsers.add_parser("proxy")
    proxy.add_argument("--port", type=int, default=8888)
    gateway = subparsers.add_parser("gateway")
    gateway.add_argument("mapping", nargs="+", type=parse_mapping)
    args = parser.parse_args()
    if args.command == "proxy":
        if os.environ.get("REQUIRE_DENY_ADDRESSES") == "1" and not DENIED_NETWORKS:
            parser.error("BROWSER_DENY_ADDRESSES must include deployment host addresses")
        run_proxy(args.port)
    else:
        run_gateways(args.mapping)


if __name__ == "__main__":
    main()
