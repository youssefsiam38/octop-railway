# Third-party notices

| Component | Licence | Use |
|---|---|---|
| Octop (`ghcr.io/tencentcloud/octop`) | MIT, © 2026 Octop. Full text in `licenses/OCTOP-LICENSE` | Base image, used unmodified |
| Caddy (`caddy` official image) | Apache-2.0 | Binary copied into the wrapper image, used unmodified |
| Python `websockets` | BSD-3-Clause | Test-only (installed on demand by `tests/lib.sh`), not shipped |

The template's own files (Dockerfile, Caddyfile, scripts, tests, docs) are MIT. See `LICENSE`.

## Trademarks

"Octop" and "Tencent Cloud" are names of their respective owners. This template is community-maintained and is not
affiliated with, endorsed by, or an official offering of the Octop project or Tencent. It uses its own generic icon
(`assets/icon.png`) and no upstream logos.
