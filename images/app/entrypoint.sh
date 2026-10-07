#!/usr/bin/env bash
# Combined entrypoint for the Octop Railway template.
#
# 1. Validates the generated admin password on first boot (upstream would otherwise silently swap a
#    rejected password for a random one written only to a file on the volume).
# 2. Starts Octop through its own upstream entrypoint (which creates the admin from
#    OCTOP_ADMIN_USERNAME / OCTOP_DEFAULT_PASSWORD on first boot), bound to loopback only.
# 3. Runs a one-shot bootstrap (bootstrap.py) that does what the web setup wizard would have done:
#    set the admin's language and create the default assistant.
# 4. Starts Caddy on the public $PORT. If either process exits, the container exits so Railway
#    restarts it. Secrets are never printed.
set -euo pipefail

log() { printf '[octop-railway] %s\n' "$*"; }
die() { printf '[octop-railway] ERROR: %s\n' "$*" >&2; exit 1; }

export HOME="${HOME:-/data}"
export OCTOP_INTERNAL_PORT="${OCTOP_INTERNAL_PORT:-8088}"
export OCTOP_PORT="$OCTOP_INTERNAL_PORT"
OCTOP_HOME="${HOME}/.octop"
mkdir -p "$OCTOP_HOME"

[ "${PORT:-8080}" != "$OCTOP_INTERNAL_PORT" ] || die "PORT must differ from OCTOP_INTERNAL_PORT ($OCTOP_INTERNAL_PORT)."

if [ ! -f "$OCTOP_HOME/octop.db" ]; then
  pw="${OCTOP_DEFAULT_PASSWORD:-}"
  [ -n "$pw" ] || die "OCTOP_DEFAULT_PASSWORD is not set. It is the initial admin password (user: ${OCTOP_ADMIN_USERNAME:-admin})."
  [ "${#pw}" -ge 8 ] || die "OCTOP_DEFAULT_PASSWORD is too short; Octop requires at least 8 characters."
  [[ "$pw" =~ [A-Za-z] && "$pw" =~ [0-9] ]] || die "OCTOP_DEFAULT_PASSWORD must contain both letters and digits."
  unset pw
  log "first boot: Octop will create the admin account '${OCTOP_ADMIN_USERNAME:-admin}' from the environment"
fi

log "starting Octop on 127.0.0.1:${OCTOP_INTERNAL_PORT}"
docker-entrypoint.sh octop run --host 127.0.0.1 --port "$OCTOP_INTERNAL_PORT" &
APP_PID=$!

python3 /usr/local/lib/octop-railway/bootstrap.py &

log "front door starting on :${PORT:-8080} (setup-wizard API closed)"
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY_PID=$!

shutdown() { kill -TERM "$APP_PID" "$CADDY_PID" 2>/dev/null || true; }
trap shutdown TERM INT

# Exit as soon as either long-running process stops, taking the other down with it.
set +e
wait -n "$APP_PID" "$CADDY_PID"
status=$?
set -e
log "a process exited (status $status); stopping"
shutdown
wait || true
exit "$status"
