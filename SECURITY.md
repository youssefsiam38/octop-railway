# Security

## What the template enforces

- **No anonymous setup wizard.** Upstream Octop (verified on `1.0.2b6`) serves `POST /api/setup/resume-wizard`
  without authentication while exactly one user exists. That is the normal state of a fresh single-admin
  instance. The wizard token it returns is accepted by `POST /api/setup/finish`, which can register an LLM provider
  with an arbitrary `base_url` and make it the **active model**. A stranger could then receive every prompt and
  reply, and the condition persists until a second user is created. This template's Caddy front door returns `403`
  for every `/api/setup/*` request except `GET /api/setup/status` and `GET /api/setup/presets` (read-only, used by
  the web app on load). The tests also try path-normalisation bypasses (`/./`, `%2F`, `..`, `//`).
- **Admin from the environment.** The admin is created on first boot from `OCTOP_ADMIN_USERNAME` and a generated
  `OCTOP_DEFAULT_PASSWORD`, so there is no first-visitor setup page to claim. Octop has no public sign-up; the admin
  creates additional users.
- **Octop is not exposed directly.** It listens on `127.0.0.1` only; Caddy is the sole listener.
- **Fail loudly on a bad password.** If the configured password fails Octop's policy, the container stops with an
  error instead of silently generating a different one.

## What you should do

- **Change the generated admin password** after the first sign-in (avatar menu → Change password). The template
  variable only seeds the very first boot.
- Note that upstream also writes the initial credentials to `/data/.octop/credential.txt` (mode 600) on the volume.
  Delete that file once you have changed the password if that matters to you.
- Agents run tools inside the container, including a sandboxed shell over their workspace. Only give accounts to
  people you trust, and review the tool and HITL approval settings in Octop.
- LLM API keys you save in Octop are stored in its database on the volume. Treat the volume and its backups as
  secret.
- Back up the `/data` volume.

## Reporting

Template issues: open an issue on https://github.com/youssefsiam38/octop-railway. Octop issues: follow upstream's
`SECURITY.md` at https://github.com/TencentCloud/Octop.
