# Maintenance

## Updating to a new Octop version

1. **Bump the upstream pin.** Get the new digest (see `UPSTREAM.md`) and update `ARG OCTOP_IMAGE=` in
   `images/app/Dockerfile`.
2. **Run the tests locally.**
   ```bash
   tests/static.sh
   docker compose build
   tests/smoke.sh
   tests/persistence.sh
   ```
3. **Cut a release tag** (`git tag -a v1.0.1 -m v1.0.1 && git push origin v1.0.1`). `publish-image.yml` re-runs the
   tests, then pushes `ghcr.io/youssefsiam38/octop-railway:{1.0.1,1.0,latest}`.
4. **Re-point the template** at the new wrapper digest (`_audit/spec_octop.py` → `patch_template`), run a clean-room
   deploy and `tests/railway-smoke.sh`, then publish the update.

## Rebuilding the Railway template from scratch

The exact configuration is in `RAILWAY_TEMPLATE.md`. The generator spec is `_audit/spec_octop.py`, and the kit in
`_audit/` (`tplkit.py`) builds a skeleton, patches the template, and runs a clean-room deploy. Only `skeleton()` sets
volumes, domains and health checks, so changing any of those means rebuilding from a skeleton.

## Gotchas worth remembering

- **The setup-wizard API is the reason for the wrapper.** With exactly one user, `POST /api/setup/resume-wizard` is
  anonymous upstream, and its token can inject an LLM provider through `/api/setup/finish`. Keep the Caddy block
  and its bypass tests in place.
- **`octop init` does not create the default assistant.** Only the wizard's `/setup/finish` does. `bootstrap.py`
  calls it over loopback with the admin token (allowed upstream while one user exists).
- **Upstream defaults the admin locale to `zh`.** The default assistant is created in the admin's locale, which is
  why `bootstrap.py` sets `OCTOP_ADMIN_LOCALE` (default `en`) before calling `/setup/finish`.
- **The password policy is silent upstream.** A password that fails the policy (8+ characters, letters and digits,
  not common) is replaced by a random one. The template generator appends `Aa1` to a random alphanumeric string, and
  the entrypoint refuses to boot on a non-compliant value.
- **`HOME` must be `/data`.** Octop stores everything under `~/.octop`.
- **The image is large (~3 GB, amd64 only)**, mostly from the Playwright browser extra and CJK fonts. Expect a slow
  first pull.
- **Local tests: avoid inheriting `ADMIN_PASSWORD`.** `tests/lib.sh` deliberately ignores a generic
  `ADMIN_PASSWORD` from the caller's environment; use `OCTOP_TEST_ADMIN_PASSWORD` or `ADMIN_PASSWORD_FILE`.
