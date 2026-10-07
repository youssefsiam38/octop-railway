#!/usr/bin/env python3
"""
A tiny, dependency-free OpenAI-compatible endpoint used ONLY by the test suite.

Octop talks to an LLM provider you configure in its Settings. Rather than spend a
real OpenAI key to prove the deployment wiring, the tests register this stub as an
OpenAI-compatible provider and chat with an agent through it. It implements just
enough of the OpenAI HTTP API for a provider test and a chat turn to run end to end:

  POST /v1/audio/transcriptions  -> {"text": "..."}            (Whisper connector)
  POST /v1/chat/completions      -> chat completion / SSE      (summaries, titles, chat)
  GET  /v1/models                -> a small model list
  GET  /healthz                  -> 200 (sidecar readiness)

It is NOT part of the Railway template — the published template talks to a real
provider you configure. Standard library only, so it runs on a bare python image.
"""
import json
import os
import socket
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("MOCK_PORT", "8080"))

TRANSCRIPT = (
    "This is a mock transcript produced by the octop-railway test suite. "
    "Alice walked through the quarterly roadmap and Bob agreed to own the migration."
)
SUMMARY = (
    "Mock reply from the octop-railway test suite: the agent reached the provider."
)


def _log(msg):
    sys.stderr.write(f"[mock-openai] {msg}\n")
    sys.stderr.flush()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send_json(self, obj, status=200):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        return self.rfile.read(length) if length else b""

    def log_message(self, fmt, *args):  # quieter default logging
        _log(fmt % args)

    def do_GET(self):
        if self.path.rstrip("/") in ("/healthz", ""):
            self._send_json({"status": "ok"})
            return
        if self.path.startswith("/v1/models"):
            self._send_json({
                "object": "list",
                "data": [
                    {"id": "whisper-1", "object": "model", "owned_by": "mock"},
                    {"id": "gpt-4o-mini", "object": "model", "owned_by": "mock"},
                ],
            })
            return
        self._send_json({"error": {"message": f"not found: {self.path}"}}, status=404)

    def do_POST(self):
        raw = self._read_body()
        path = self.path.split("?", 1)[0]

        if path.endswith("/audio/transcriptions") or path.endswith("/audio/translations"):
            # multipart request from the Whisper connector; we ignore the audio
            # and return a deterministic transcript.
            self._send_json({"text": TRANSCRIPT})
            return

        if path.endswith("/chat/completions"):
            stream = False
            try:
                stream = bool(json.loads(raw or b"{}").get("stream"))
            except Exception:
                stream = False
            if stream:
                self._send_chat_stream(SUMMARY)
            else:
                self._send_chat_json(SUMMARY)
            return

        if path.endswith("/embeddings"):
            self._send_json({
                "object": "list",
                "data": [{"object": "embedding", "index": 0, "embedding": [0.0] * 8}],
                "model": "mock-embed",
                "usage": {"prompt_tokens": 1, "total_tokens": 1},
            })
            return

        self._send_json({"error": {"message": f"not found: {path}"}}, status=404)

    def _send_chat_json(self, content):
        self._send_json({
            "id": "chatcmpl-mock",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": "gpt-4o-mini",
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": content},
                "finish_reason": "stop",
            }],
            "usage": {"prompt_tokens": 10, "completion_tokens": 10, "total_tokens": 20},
        })

    def _send_chat_stream(self, content):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()

        def chunk(delta, finish=None):
            payload = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": "gpt-4o-mini",
                "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
            }
            self.wfile.write(f"data: {json.dumps(payload)}\n\n".encode())
            self.wfile.flush()

        chunk({"role": "assistant"})
        chunk({"content": content})
        chunk({}, finish="stop")
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()


class DualStackServer(ThreadingHTTPServer):
    # Bind IPv6 with V6ONLY off so both Railway's IPv6 private network and a plain
    # IPv4 docker bridge can reach the stub from a single socket.
    address_family = socket.AF_INET6

    def server_bind(self):
        try:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        except (AttributeError, OSError):
            pass
        super().server_bind()


def main():
    server = DualStackServer(("::", PORT), Handler)
    _log(f"listening on [::]:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
