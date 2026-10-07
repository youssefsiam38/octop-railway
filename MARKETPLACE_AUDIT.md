# Marketplace audit — Octop

## Identity

| | |
|---|---|
| Upstream | https://github.com/TencentCloud/Octop (7.5k★, active; latest release `v1.0.2b6`, 2026-10-04) |
| What | Self-hosted, multi-user, multi-agent AI assistant (FastAPI + React), BYO LLM provider |
| Image | `ghcr.io/tencentcloud/octop:1.0.2b6@sha256:80d3a75f…b18909` (amd64), wrapped with Caddy |
| Marketplace gap | 2 existing "Octop" templates, best has 0 deploys at audit time |

## Licence and brand

- `LICENSE`: MIT ("Permission is hereby granted, free of charge, to any person obtaining a copy…"). Commercial
  redistribution in a paid template is fine.
- No upstream logo used; generic icon; non-affiliation stated in README, OVERVIEW and THIRD_PARTY_NOTICES.

## Self-hostability

- One container, SQLite by default (Postgres optional, not needed). Port 8088, health `/api/health`, data under
  `$HOME/.octop`.
- No GPU, no Docker socket, and no privileged mode on the core path. The mobile/Android overlay needs these, but it
  is a separate compose file and is not used here.
- No build-time-baked URLs (the web app is served by the same server).

## Security review

| Finding | Severity | Template mitigation |
|---|---|---|
| `POST /api/setup/resume-wizard` is anonymous while user count == 1; its token lets `/api/setup/finish` add a provider with any `base_url` and set it active (verified locally on `1.0.2b6`) | High: conversation exfiltration / model hijack on any fresh single-admin instance | Caddy front door refuses `/api/setup/*` except GET `status`/`presets`; tested incl. `/./`, `%2F`, `..`, `//` bypasses |
| First admin normally created by a web wizard | Medium (race) | Admin from env (`octop init` in upstream entrypoint) |
| Rejected initial password silently replaced by a random one stored only on the volume | Low (lock-out) | Generator guarantees policy (`…Aa1`); entrypoint refuses to boot on a non-compliant value |
| No public sign-up | none | admin creates users |
| Agents run a sandboxed shell over their workspace | by design | documented in SECURITY.md |

The setup-wizard issue should be reported upstream privately (per upstream `SECURITY.md`).

## Tests

| Script | Assertions | Covers |
|---|---|---|
| `tests/static.sh` | 30 | syntax (bash+python), shellcheck, compose shape, three digest pins, env wiring, Caddy posture, secret scan |
| `tests/smoke.sh` | 30 | health, web app, 11 setup-API refusals + status readable, 401 without token, wrong password, admin login, locale, default assistant, provider create + test, active model, agent, thread, chat over WebSocket via mock, history |
| `tests/persistence.sh` | 28 | seed product flow, recreate container, admin/locale/provider/agent/history kept, no duplicate default assistant, setup still closed |
| `tests/railway-smoke.sh` | live | the smoke flow over HTTPS against a deployment with a mock sidecar; `VERIFY_ONLY=1` re-check after redeploy |

## Deploy-time inputs

None required. Generated: `OCTOP_DEFAULT_PASSWORD`. Defaults: `OCTOP_ADMIN_USERNAME=admin`, `OCTOP_ADMIN_LOCALE=en`.
The user adds the LLM provider in-app.

## Verdict

**SHIPPABLE** as a combined wrapper (official image + Caddy front door), one service, one volume.
