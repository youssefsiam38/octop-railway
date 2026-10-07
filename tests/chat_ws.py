#!/usr/bin/env python3
"""Send one chat turn to an Octop agent over its dashboard WebSocket and print the reply text.

Usage: chat_ws.py BASE_URL AGENT_ID THREAD_ID MESSAGE   (JWT read from $OCTOP_TOKEN_FILE)
Exit 0 when a non-empty assistant reply arrives before the turn's "done" frame.
"""
import asyncio
import json
import os
import sys

import websockets


async def main() -> int:
    base, agent, thread, text = sys.argv[1:5]
    with open(os.environ["OCTOP_TOKEN_FILE"]) as fh:
        token = fh.read().strip()
    ws_url = base.replace("https://", "wss://").replace("http://", "ws://")
    uri = f"{ws_url}/api/agents/{agent}/chat/ws?token={token}"
    reply, frames = [], []
    async with websockets.connect(uri, open_timeout=30, max_size=None) as ws:
        await ws.send(json.dumps({"type": "user_turn", "thread_id": thread, "text": text}))
        while True:
            raw = await asyncio.wait_for(ws.recv(), timeout=120)
            frame = json.loads(raw)
            kind = frame.get("type")
            frames.append(kind)
            if kind == "error":
                print(f"error frame: {frame.get('message')}", file=sys.stderr)
            for key in ("content", "text", "delta"):
                val = frame.get(key)
                if isinstance(val, str):
                    reply.append(val)
            if kind == "done":
                break
    out = "".join(reply).strip()
    print(out)
    if not out:
        print(f"frames: {frames}", file=sys.stderr)
    return 0 if out else 1


sys.exit(asyncio.run(main()))
