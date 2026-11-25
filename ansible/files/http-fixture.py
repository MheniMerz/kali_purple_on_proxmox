"""Serve two benign HTTP fixtures or request one from a specific lab address."""

import http.client
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit

PORT = 18080
CONTROL = "/kali-purple-control"
POSITIVE = "/kali-purple-positive"
BODY = b"Kali Purple HTTP fixture\n"


class FixtureHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if urlsplit(self.path).path not in (CONTROL, POSITIVE):
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(BODY)))
        self.end_headers()
        self.wfile.write(BODY)
        self.server.served += 1


class FixtureServer(HTTPServer):
    def get_request(self):
        conn, address = super().get_request()
        conn.settimeout(3)
        return conn, address


def serve(address, port=PORT):
    with FixtureServer((address, port), FixtureHandler) as server:
        server.served = 0
        server.timeout = 2
        deadline = time.monotonic() + 60
        while server.served < 2 and time.monotonic() < deadline:
            server.handle_request()
        if server.served != 2:
            raise SystemExit(f"Only served {server.served} of 2 fixture requests")


def request(source, destination, kind, run_id, port=PORT):
    paths = {"control": CONTROL, "positive": POSITIVE}
    conn = http.client.HTTPConnection(destination, port, timeout=8, source_address=(source, 0))
    try:
        conn.connect()
        _, source_port = conn.sock.getsockname()
        conn.request("GET", f"{paths[kind]}?run={run_id}")
        response = conn.getresponse()
        if response.status != 200 or response.read() != BODY:
            raise SystemExit(f"{kind} fixture returned unexpected HTTP response {response.status}")
        print(json.dumps({"kind": kind, "source_port": source_port}))
    finally:
        conn.close()


if __name__ == "__main__":
    mode, *args = sys.argv[1:]
    if mode == "serve":
        serve(*args)
    else:
        request(*args)
