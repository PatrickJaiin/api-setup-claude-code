#!/usr/bin/env python3
"""Mock LiteLLM router for tests.

Serves the two endpoints glm-claude touches: GET /health/liveliness and
POST /v1/messages (returns a canned, well-formed Anthropic message).
Usage: mock_proxy.py PORT
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.startswith("/health"):
            self._send(200, {"status": "healthy"})
        else:
            self._send(404, {"error": "not found"})

    def do_POST(self):
        self.rfile.read(int(self.headers.get("content-length", 0)))
        if self.path != "/v1/messages":
            self._send(404, {"error": "not found"})
            return
        self._send(
            200,
            {
                "id": "msg_mock_000",
                "type": "message",
                "role": "assistant",
                "model": "z-ai/glm-5.2",
                "content": [{"type": "text", "text": "OK"}],
                "stop_reason": "end_turn",
                "stop_sequence": None,
                "usage": {"input_tokens": 10, "output_tokens": 1},
            },
        )

    def log_message(self, *args):
        pass


def main():
    port = int(sys.argv[1])
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
