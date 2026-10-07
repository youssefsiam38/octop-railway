#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016
# Static validation: syntax, shellcheck, compose, upstream image pin and configuration. No Docker build.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
cd "$REPO_ROOT"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

section "syntax"
for f in tests/*.sh images/app/entrypoint.sh; do
  if bash -n "$f" 2>/dev/null; then pass "parses: $f"; else fail "syntax error: $f"; fi
done
for f in images/app/bootstrap.py tests/chat_ws.py tests/mock/mock_openai.py; do
  if python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f"; then pass "parses: $f"; else fail "syntax error: $f"; fi
done

section "shellcheck"
if command -v shellcheck >/dev/null; then
  if shellcheck -x -s bash tests/*.sh images/app/entrypoint.sh; then pass "shellcheck"; else fail "shellcheck"; fi
else
  echo "  SKIP  shellcheck not installed"
fi

section "compose"
if docker compose -f compose.yaml config -q; then pass "compose config"; else fail "compose config"; fi
cfg=$(docker compose -f compose.yaml config --format json)
assert_eq "services" "app mock" "$(jq -r '[.services | keys[]] | sort | join(" ")' <<<"$cfg")"
assert_eq "the front door binds to loopback" "127.0.0.1" "$(jq -r '[.services.app.ports[]? | .host_ip] | join(" ")' <<<"$cfg")"
assert_eq "the front door listens on 8080" "8080" "$(jq -r '[.services.app.ports[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "the /data volume is mounted" "/data" "$(jq -r '[.services.app.volumes[]? | .target] | join(" ")' <<<"$cfg")"
assert_eq "the mock provider is not published" "" "$(jq -r '[.services.mock.ports[]? | .published] | join(" ")' <<<"$cfg")"

section "image pins"
df=$(cat images/app/Dockerfile)
assert_contains "the wrapper builds FROM the official Octop image, pinned by digest" \
  '^ARG OCTOP_IMAGE=ghcr.io/tencentcloud/octop:[^@]*@sha256:[0-9a-f]\{64\}$' "$(grep '^ARG OCTOP_IMAGE=' images/app/Dockerfile)"
assert_contains "Caddy is pinned by digest" '^ARG CADDY_IMAGE=caddy:[^@]*@sha256:[0-9a-f]\{64\}$' "$(grep '^ARG CADDY_IMAGE=' images/app/Dockerfile)"
assert_contains "the mock image is pinned by digest" '@sha256:[0-9a-f]\{64\}' "$(jq -r '.services.mock.image' <<<"$cfg")"
assert_contains "HOME points Octop's data at the volume" 'HOME=/data' "$df"

section "configuration"
env_json=$(jq -r '.services.app.environment' <<<"$cfg")
assert_contains "the admin password is wired" 'OCTOP_DEFAULT_PASSWORD' "$env_json"
assert_contains "the compose admin password is a placeholder" 'localTestOnly' "$(jq -r '.services.app.environment.OCTOP_DEFAULT_PASSWORD' <<<"$cfg")"
assert_eq "Langfuse tracing is off" "false" "$(jq -r '.services.app.environment.LANGFUSE_TRACING_ENABLED' <<<"$cfg")"
assert_contains "Octop is bound to loopback" '--host 127.0.0.1' "$(cat images/app/entrypoint.sh)"
assert_contains "first boot validates the admin password" 'must contain both letters and digits' "$(cat images/app/entrypoint.sh)"

section "front door posture"
cf=$(cat images/app/Caddyfile)
assert_contains "the Caddyfile matches the setup API" 'path /api/setup /api/setup/\*' "$cf"
assert_contains "the setup API is refused with 403" 'respond .* 403' "$cf"
assert_contains "only status/presets GETs are exempt" 'path /api/setup/status /api/setup/presets' "$cf"
assert_contains "the bootstrap only talks to loopback" 'http://127.0.0.1' "$(cat images/app/bootstrap.py)"

section "secrets hygiene"
mapfile -t tracked < <(git ls-files 2>/dev/null | grep . || find . -type f -not -path './.git/*' -not -path './test-output/*')
if [ "${#tracked[@]}" -gt 0 ] && grep -lE '(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "${tracked[@]}" 2>/dev/null; then
  fail "a credential-shaped string is in the repository"
else
  pass "no credential-shaped strings in ${#tracked[@]} files"
fi

summary
