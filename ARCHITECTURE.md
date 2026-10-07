# Architecture

```
            Railway HTTPS edge
                    │  :8080 (PORT)
┌───────────────────▼──────────────────────────────── app (one service) ─┐
│  Caddy front door                                                       │
│    /api/setup/*  ──► 403   (except GET status / presets)                │
│    everything else ──► reverse_proxy 127.0.0.1:8088 (incl. WebSockets)  │
│                              │                                          │
│  Octop (official image, unmodified)  octop run --host 127.0.0.1         │
│    SQLite + agent workspaces + uploads  ──►  /data/.octop  (volume)     │
│  bootstrap.py (one-shot, loopback): admin locale + default assistant    │
└─────────────────────────────────────────────────────────────────────────┘
                    │ outbound
                    ▼
          your LLM provider (configured in Settings → Models)
```

## The service

| | |
|---|---|
| Image | `ghcr.io/youssefsiam38/octop-railway` = `FROM ghcr.io/tencentcloud/octop@sha256:…` + Caddy binary + entrypoint |
| Public port | `PORT=8080` (Caddy). Octop listens on `127.0.0.1:8088` (`OCTOP_INTERNAL_PORT`) |
| Health check | `GET /api/health` (Octop's public health route, proxied by Caddy, so it reflects the app's real state) |
| Volume | `/data` (`HOME=/data`, so Octop's `~/.octop` lands on it) |
| Runs as | root (the upstream image has no `USER`), so the root-owned Railway volume is writable |

## Start-up sequence (`images/app/entrypoint.sh`)

1. On first boot (no `octop.db` yet), check that `OCTOP_DEFAULT_PASSWORD` meets Octop's password policy (at least
   8 characters, letters and digits). If it doesn't, exit with an error. Upstream would otherwise quietly replace a
   rejected password with a random one written only to `/data/.octop/credential.txt`.
2. Run the upstream `docker-entrypoint.sh octop run --host 127.0.0.1 --port 8088`. On first boot it runs
   `octop init` to create the admin from `OCTOP_ADMIN_USERNAME` / `OCTOP_DEFAULT_PASSWORD`.
3. Start `bootstrap.py` in the background. It waits for health, signs in over loopback, sets the admin's locale
   (`OCTOP_ADMIN_LOCALE`), and calls `POST /api/setup/finish` with the admin's token so Octop creates its default
   assistant, which the web wizard would normally do. A marker on the volume makes it run once.
4. Start Caddy, then `wait -n`: if either Octop or Caddy exits, the container exits and Railway restarts it.

## Why a wrapper, and why one container

The upstream image works on Railway as-is, with one exception: its setup-wizard API is reachable anonymously while
there is a single user (see SECURITY.md). Octop has no setting to turn the wizard off, and this template doesn't
patch the app. A reverse proxy that refuses that path prefix is the smallest fix. Caddy runs in the same container
and reaches Octop over loopback, so Octop never listens on a routable interface. That rules out a bypass through the
private network and keeps the template to one service and one volume.

Caddy passes Railway's `X-Forwarded-For` through unchanged. Octop trusts the right-most entry from a loopback peer,
and that entry is the address Railway's edge saw, so Octop's per-IP throttles key on the real client.
