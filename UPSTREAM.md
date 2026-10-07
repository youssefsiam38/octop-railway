# Upstream

| | |
|---|---|
| Project | Octop, https://github.com/TencentCloud/Octop |
| Licence | MIT (`licenses/OCTOP-LICENSE`) |
| Official image | `ghcr.io/tencentcloud/octop` (published by upstream's `docker-publish.yml` on `v*` tags) |
| Pinned version | `1.0.2b6` |
| Pinned digest | `sha256:80d3a75ffafef1108b520b6b28e7c802c0ece3c6edbf5f26edae9f7d14b18909` (OCI index; `linux/amd64`) |
| Caddy | `caddy:2.10.2@sha256:c3d7ee5d2b11f9dc54f947f68a734c84e9c9666c92c88a7f30b9cba5da182adb` (binary copied in) |
| Wrapper image | `ghcr.io/youssefsiam38/octop-railway` (see `RAILWAY_TEMPLATE.md` for the digest the template uses) |

Octop is used **unmodified**. The wrapper adds the Caddy binary, a Caddyfile, an entrypoint and a one-shot
bootstrap script. It does not change any Octop file.

## Refreshing the digest

```bash
docker buildx imagetools inspect ghcr.io/tencentcloud/octop:<version> | sed -n 3p   # Digest: sha256:…
```

Update `ARG OCTOP_IMAGE=` in `images/app/Dockerfile` and this file, then follow `MAINTENANCE.md`. Upstream currently
tags beta releases (`1.0.2bN`) every few days. Re-check the setup-wizard behaviour described in `SECURITY.md` on each
bump; if upstream closes it, the front door becomes defence-in-depth rather than a requirement.
