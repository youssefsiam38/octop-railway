# Railway template configuration

The template's exact configuration. Reproduce it from this file if it ever has to be rebuilt.

| | |
|---|---|
| Name | Octop |
| Code | `octop-2` |
| Template id | `0f8383d8-1475-417d-a86e-9b51d37347a8` |
| Deploy URL | https://railway.com/deploy/octop-2 |
| Category | AI/ML |
| Card description | Self-hosted multi-agent AI assistant with your own LLM provider |
| Icon | `assets/icon.png` |
| Overview markdown | `marketplace/OVERVIEW.md` (Railway enforces its section headings) |

Generated values use Railway's `secret()` function: `hexN` is `${{secret(N, "abcdef0123456789")}}` and `alnumN` is
`${{secret(N, "a-zA-Z0-9")}}` spelled out. Alphanumeric passwords are used wherever a value is embedded in a
connection URL, so nothing needs percent-encoding. The wrapper image is referenced by tag and digest;
`UPSTREAM.md` records the upstream digests.

## Services

### `app`

| Field | Value |
|---|---|
| Source | `ghcr.io/youssefsiam38/octop-railway:1.0.0@sha256:a6f8770ecf0d833b3967af1fd80f2d108052d445481839af011cbbc11dc23830` |
| Public domain | target port 8080 |
| Volume | `/data` |
| Healthcheck | `/api/health`, timeout from `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` |
| Restart policy | on failure, 10 retries |

| Variable | Value |
|---|---|
| `PORT` | `8080` |
| `OCTOP_ADMIN_USERNAME` | `admin` |
| `OCTOP_DEFAULT_PASSWORD` | generated, alnum24 followed by `Aa1` |
| `OCTOP_ADMIN_LOCALE` | `en` |
| `LANGFUSE_TRACING_ENABLED` | `false` |
| `FORWARD_PROTO` | `https` |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | `300` |

## Notes

- Wrapper: official `ghcr.io/tencentcloud/octop:1.0.2b6` + Caddy in one container. Caddy (public `:8080`) refuses `/api/setup/*` except GET `status`/`presets`; Octop listens on `127.0.0.1:8088`.
- Why: upstream's `POST /api/setup/resume-wizard` is anonymous while the instance has exactly one user, and its token lets `/api/setup/finish` register an LLM provider with any `base_url` and make it the active model.
- Admin from env (`OCTOP_ADMIN_USERNAME`, generated `OCTOP_DEFAULT_PASSWORD` = 24 alnum + `Aa1` to satisfy Octop's letters+digits policy). A one-shot loopback bootstrap sets `OCTOP_ADMIN_LOCALE` (upstream defaults to `zh`) and creates the default assistant via `/api/setup/finish` with the admin JWT.
- `HOME=/data` keeps `~/.octop` (SQLite, agent workspaces, uploads) on the volume.
- Verified live: setup API refused incl. `/./`, `%2F`, `..`, `//` bypasses; admin login; provider (mock sidecar) test; agent + thread + chat turn over `wss://`; history; all kept across a redeploy.
