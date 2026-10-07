#!/usr/bin/env python3
"""One-shot first-run bootstrap for the Octop Railway template (standard library only).

Octop's web setup wizard normally creates the admin, then calls ``POST /api/setup/finish`` to create
the default assistant. This template creates the admin from environment variables instead and keeps
the wizard API closed at the public front door, so this script finishes the job over loopback:

  1. waits for Octop to answer on 127.0.0.1;
  2. signs in as the env-created admin;
  3. sets the admin's language to ``OCTOP_ADMIN_LOCALE`` (default ``en``; upstream defaults to ``zh``);
  4. if the admin has no agents yet, calls ``/api/setup/finish`` (admin token, no provider) so Octop
     creates its default assistant exactly as the wizard would.

It runs once: a marker file on the volume records completion. The password is read from the
environment and never printed. Failure is logged and is not fatal; Octop still works without it.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

HOME = os.environ.get("HOME", "/data")
MARKER = os.path.join(HOME, ".octop", ".railway-bootstrap-done")
BASE = f"http://127.0.0.1:{os.environ.get('OCTOP_INTERNAL_PORT', '8088')}"


def log(msg: str) -> None:
    print(f"[octop-railway] bootstrap: {msg}", flush=True)


def call(method: str, path: str, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else None


def main() -> int:
    if os.path.exists(MARKER):
        return 0
    deadline = time.time() + 600
    while True:
        try:
            if call("GET", "/api/health").get("ok"):
                break
        except (urllib.error.URLError, OSError, ValueError):
            pass
        if time.time() > deadline:
            log("Octop did not become healthy; skipping")
            return 0
        time.sleep(3)

    password = os.environ.get("OCTOP_DEFAULT_PASSWORD", "")
    username = os.environ.get("OCTOP_ADMIN_USERNAME", "admin")
    try:
        token = call("POST", "/api/auth/login", {"username": username, "password": password})["access_token"]
    except urllib.error.HTTPError as exc:
        # The admin changed the password in the app (expected on later boots of older volumes).
        log(f"admin sign-in refused ({exc.code}); skipping")
        return 0

    locale = os.environ.get("OCTOP_ADMIN_LOCALE", "en").strip() or "en"
    call("PATCH", "/api/auth/me", {"locale": locale}, token)

    agents = call("GET", "/api/agents", token=token) or []
    if not agents:
        call("POST", "/api/setup/finish", {}, token)
        log("default assistant created")

    with open(MARKER, "w") as fh:
        fh.write(time.strftime("%Y-%m-%dT%H:%M:%SZ\n", time.gmtime()))
    log(f"done (language: {locale})")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - never take the container down
        log(f"failed: {type(exc).__name__}: {exc}")
        sys.exit(0)
