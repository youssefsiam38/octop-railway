# syntax=docker/dockerfile:1
#
# Combined image for the Octop Railway template: the official Octop image plus a Caddy front door in
# the same container. Caddy is the only public listener; Octop runs on loopback (127.0.0.1:8088).
# The front door blocks Octop's first-run setup-wizard API (/api/setup/*), which upstream leaves
# reachable without authentication while the instance has a single user. Octop itself is unmodified.
ARG OCTOP_IMAGE=ghcr.io/tencentcloud/octop:1.0.2b6@sha256:80d3a75ffafef1108b520b6b28e7c802c0ece3c6edbf5f26edae9f7d14b18909
ARG CADDY_IMAGE=caddy:2.10.2@sha256:c3d7ee5d2b11f9dc54f947f68a734c84e9c9666c92c88a7f30b9cba5da182adb

FROM ${CADDY_IMAGE} AS caddy

FROM ${OCTOP_IMAGE}
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown

# Caddy is a static Go binary; copy it from the official image.
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY images/app/Caddyfile /etc/caddy/Caddyfile
COPY --chmod=0755 images/app/entrypoint.sh /usr/local/bin/octop-railway-entrypoint
COPY images/app/bootstrap.py /usr/local/lib/octop-railway/bootstrap.py

# Octop keeps everything (SQLite DB, agent workspaces, uploads) under $HOME/.octop -> the /data volume.
ENV HOME=/data \
    OCTOP_INTERNAL_PORT=8088 \
    PORT=8080

LABEL org.opencontainers.image.title="octop-railway" \
      org.opencontainers.image.description="Octop plus a Caddy front door for the Octop Railway template. Not affiliated with the Octop project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/octop-railway" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

EXPOSE 8080
# Replace upstream's HEALTHCHECK (it probes the internal port) with the public one.
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD ["sh", "-c", "curl -fsS http://127.0.0.1:${PORT:-8080}/api/health >/dev/null || exit 1"]

ENTRYPOINT ["/usr/local/bin/octop-railway-entrypoint"]
CMD []
