# Octop on Railway

A one-click [Railway](https://railway.com) template that runs [Octop](https://github.com/TencentCloud/Octop), an
open-source, self-hosted, multi-user and multi-agent AI assistant. You bring your own LLM provider (OpenAI or any
OpenAI-compatible endpoint, Anthropic, DeepSeek, Qwen, Ollama and others), then create agents with skills, knowledge
bases, MCP tools and scheduled tasks for yourself and your team.

> **Community-maintained and not affiliated.** This template is based on Octop but is **not affiliated with,
> endorsed by, or an official offering of** the Octop project or Tencent Cloud, and it does not use the Octop logo.
> See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

- **Image:** the official `ghcr.io/tencentcloud/octop`, pinned by digest and used **unmodified**. It is packaged
  with a small Caddy front door in the same container. See [UPSTREAM.md](UPSTREAM.md) and
  [ARCHITECTURE.md](ARCHITECTURE.md).
- Octop is **MIT** licensed, and the template's own files are MIT too.

## Why the front door

Octop creates its first admin through a web setup wizard. The wizard's API stays reachable **without
authentication** while the instance has only one user. During that time, anyone who finds the URL can register an
LLM provider with their own base URL and make it the active model, which silently routes every conversation to
them. This template creates the admin from environment variables, so the wizard is never needed. Caddy refuses
`/api/setup/*` at the edge; only the two read-only GETs the web app uses (`status`, `presets`) are allowed through.
Octop's own login protects everything else. Details are in [SECURITY.md](SECURITY.md).

## What you get

- One service: Octop on a private loopback port, with Caddy as the only public listener. The SQLite database, agent
  workspaces and uploads live on a `/data` volume.
- An **admin account created on first boot**: user `OCTOP_ADMIN_USERNAME` (default `admin`) with a generated
  password `OCTOP_DEFAULT_PASSWORD`.
- A one-shot first-run bootstrap does what the wizard would have done: it sets the admin's language
  (`OCTOP_ADMIN_LOCALE`, default `en`) and creates Octop's default assistant.

## Deploy

1. Click **Deploy on Railway** and wait for the service to go healthy. The first boot takes about a minute.
2. Open the service → **Variables** and copy `OCTOP_DEFAULT_PASSWORD`.
3. Open the public domain and sign in as `admin` with that password. Change it under avatar menu → Change password.
4. Go to **Settings → Models** and add your LLM provider and API key, then start chatting with the default
   assistant or create your own agents.

`OCTOP_DEFAULT_PASSWORD` only matters on the very first boot. After that, the password you set in the app is the one
that counts.

## Security

See [SECURITY.md](SECURITY.md). In short: change the generated admin password, keep the front door in place, and
back up the `/data` volume.

## Repository layout

| Path | What |
|---|---|
| `images/app/` | The combined wrapper: official Octop image + Caddy front door (`Dockerfile`, `Caddyfile`, `entrypoint.sh`, `bootstrap.py`) |
| `compose.yaml` | Local test topology (the wrapper + a test-only mock LLM provider) |
| `tests/` | Static, smoke, persistence, and live (HTTPS) tests; `chat_ws.py` drives a chat turn; `mock/` is the stub provider |
| `marketplace/OVERVIEW.md` | The marketplace overview shown on the template page |
| `RAILWAY_TEMPLATE.md` | The exact published template configuration |
| `UPSTREAM.md` · `SECURITY.md` · `ARCHITECTURE.md` · `MAINTENANCE.md` · `MARKETPLACE_AUDIT.md` | Reference docs |

## Local development

```bash
docker compose up --build   # Octop behind the front door on http://127.0.0.1:18188 (admin / localTestOnlyAdminPw1)
tests/static.sh             # syntax, shellcheck, compose shape, digest pins, front-door posture, secret scan
tests/smoke.sh              # setup API closed, admin login, provider -> agent -> chat over WebSocket via the mock
tests/persistence.sh        # provider, agent and chat history survive a container recreate
```

## Licence

The template's own files are MIT (`LICENSE`). Octop is MIT; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
