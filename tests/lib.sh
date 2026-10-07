#!/usr/bin/env bash
# shellcheck disable=SC2015
# Shared helpers for octop-railway tests. Source this file; do not execute it.
#
# Octop has its own login (JSON -> JWT). The admin is created from the environment on first boot.
# Secrets are read from files or env and never echoed: request bodies holding a password are written
# to mode-600 files under $TEST_TMP and sent with --data @file, the JWT lives in $TEST_TMP/token.

: "${APP_URL:=http://127.0.0.1:${OCTOP_TEST_PORT:-18188}}"
: "${TEST_TIMEOUT:=300}"
: "${OCTOP_ADMIN_USERNAME:=admin}"
ADMIN_USERNAME=$OCTOP_ADMIN_USERNAME
# Deliberately NOT inherited from a generic $ADMIN_PASSWORD in the caller's environment.
if [ -n "${ADMIN_PASSWORD_FILE:-}" ]; then
  ADMIN_PASSWORD=$(<"$ADMIN_PASSWORD_FILE")
else
  ADMIN_PASSWORD=${OCTOP_TEST_ADMIN_PASSWORD:-localTestOnlyAdminPw1}
fi
# Base URL Octop uses to reach the mock provider (compose service name locally; a Railway sidecar live).
: "${MOCK_BASE_URL:=http://mock:8080/v1}"

TEST_TMP="${TEST_TMP:-$(mktemp -d)}"
chmod 700 "$TEST_TMP"
export TEST_TMP
_PASS=0; _FAIL=0

pass() { _PASS=$((_PASS+1)); printf '  PASS  %s\n' "$*"; }
fail() { _FAIL=$((_FAIL+1)); printf '  FAIL  %s\n' "$*" >&2; }
die()  { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
section() { printf '\n== %s ==\n' "$*"; }
summary() { printf '\n%d passed, %d failed\n' "$_PASS" "$_FAIL"; [ "$_FAIL" -eq 0 ]; }

assert_eq() { if [ "$2" = "$3" ]; then pass "$1 ($3)"; else fail "$1: expected [$2] got [$3]"; fi; }
assert_contains() { if grep -q -- "$2" <<<"$3"; then pass "$1"; else fail "$1: missing [$2]"; fi; }

http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$@" || true; }

wait_for_code() {
  local url=$1 want=$2 timeout=${3:-$TEST_TIMEOUT} start code
  start=$(date +%s)
  while :; do
    code=$(http_code "$url")
    [ "$code" = "$want" ] && return 0
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then printf 'timed out waiting for %s -> %s (last %s)\n' "$url" "$want" "$code" >&2; return 1; fi
    sleep 3
  done
}

compose() { docker compose -f "$REPO_ROOT/compose.yaml" "$@"; }

# login_body USER PASSWORD -> path of a mode-600 JSON login body.
login_body() {
  local f="$TEST_TMP/login-$RANDOM.json"
  (umask 077; jq -nc --arg u "$1" --arg p "$2" '{username:$u,password:$p}' >"$f")
  printf '%s' "$f"
}

# login_code USER PASSWORD -> HTTP status of a sign-in attempt.
login_code() { http_code -X POST "$APP_URL/api/auth/login" -H 'Content-Type: application/json' --data "@$(login_body "$1" "$2")"; }

# login -> 0 when the admin signs in; the JWT is written to $TEST_TMP/token (mode 600).
login() {
  local resp
  resp=$(curl -s --max-time 30 -X POST "$APP_URL/api/auth/login" -H 'Content-Type: application/json' \
    --data "@$(login_body "$ADMIN_USERNAME" "$ADMIN_PASSWORD")")
  (umask 077; jq -r '.access_token // empty' <<<"$resp" >"$TEST_TMP/token")
  [ -s "$TEST_TMP/token" ]
}

# api METHOD PATH [JSON] -> body of an authenticated API call.
api() {
  local m=$1 p=$2 d=${3:-}
  local args=(-s --max-time 60 -X "$m" "$APP_URL$p" -H "Authorization: Bearer $(<"$TEST_TMP/token")" -H 'Content-Type: application/json')
  [ -n "$d" ] && args+=(--data "$d")
  curl "${args[@]}"
}
api_code() {
  local m=$1 p=$2 d=${3:-}
  local args=(-s -o /dev/null -w '%{http_code}' --max-time 60 -X "$m" "$APP_URL$p" -H "Authorization: Bearer $(<"$TEST_TMP/token")" -H 'Content-Type: application/json')
  [ -n "$d" ] && args+=(--data "$d")
  curl "${args[@]}" || true
}

# chat AGENT_ID THREAD_ID TEXT -> prints the assistant reply (WebSocket turn via tests/chat_ws.py).
chat() {
  local runner=(python3)
  if ! python3 -c 'import websockets' 2>/dev/null; then
    if command -v uv >/dev/null; then runner=(uv run -q --with websockets python); else
      python3 -m pip install -q --user websockets >/dev/null 2>&1 \
        || python3 -m pip install -q --user --break-system-packages websockets >/dev/null 2>&1 || true
    fi
  fi
  OCTOP_TOKEN_FILE="$TEST_TMP/token" "${runner[@]}" "$REPO_ROOT/tests/chat_ws.py" "$APP_URL" "$1" "$2" "$3"
}

# The setup-wizard bypass attempts the front door must refuse. Each line: METHOD PATH.
SETUP_PROBES=(
  "POST /api/setup/resume-wizard"
  "POST /api/setup/finish"
  "POST /api/setup/begin"
  "POST /api/setup/initial-admin"
  "POST /api/setup/test-provider"
  "POST /api/setup/database"
  "GET /api/setup/validate-token"
  "POST /api/setup/./resume-wizard"
  "POST /api/setup%2Fresume-wizard"
  "POST /api/x/../setup/resume-wizard"
  "POST //api/setup/resume-wizard"
)

# The setup-API checks shared by smoke and railway-smoke.
check_setup_closed() {
  local probe m p code
  for probe in "${SETUP_PROBES[@]}"; do
    m=${probe%% *}; p=${probe#* }
    code=$(http_code --path-as-is -X "$m" "$APP_URL$p" -H 'Content-Type: application/json' --data '{}')
    case "$code" in
      403|404|405) pass "front door refuses $m $p ($code)" ;;
      *) fail "front door let $m $p through ($code)" ;;
    esac
  done
  assert_eq "setup status stays readable for the web app" "200" "$(http_code "$APP_URL/api/setup/status")"
  assert_eq "the instance reports setup complete" "false" "$(curl -s --max-time 30 "$APP_URL/api/setup/status" | jq -r '.setup_required')"
}

# The product flow shared by smoke and railway-smoke: provider -> agent -> thread -> chat -> history.
# Leaves $TEST_TMP/agent and $TEST_TMP/thread for persistence checks.
check_product_flow() {
  local tag=$1 body pid aid tid reply hist
  body=$(jq -nc --arg u "$MOCK_BASE_URL" '{name:"mock",kind:"openai",base_url:$u,api_key:"mock-key",models:[{id:"mock-model",name:"mock-model",enabled:true}]}')
  # Reuse an existing "mock" provider so the flow can be re-run against the same deployment.
  pid=$(api GET /api/admin/providers | jq -r 'first(.[] | select(.name=="mock") | .id) // empty')
  [ -n "$pid" ] || pid=$(api POST /api/admin/providers "$body" | jq -r '.id // empty')
  [ -n "$pid" ] && pass "admin registers an LLM provider (id $pid)" || fail "provider create"
  assert_eq "provider round-trip test succeeds" "true" "$(api POST "/api/admin/providers/$pid/test" '{"model_id":"mock-model"}' | jq -r '.ok')"
  assert_eq "active model is set" "200" "$(api_code PUT /api/providers/active-model '{"provider_name":"mock","model":"mock-model"}')"

  aid=$(api POST /api/agents "$(jq -nc --arg n "Smoke $tag $(date +%s)" '{name:$n,default_model:"mock/mock-model"}')" | jq -r '.agent_id // empty')
  [ -n "$aid" ] && pass "agent created ($aid)" || fail "agent create"
  tid=$(api POST "/api/agents/$aid/threads" '{}' | jq -r '.thread_id // empty')
  [ -n "$tid" ] && pass "chat thread created" || fail "thread create"
  printf '%s' "$aid" >"$TEST_TMP/agent"; printf '%s' "$tid" >"$TEST_TMP/thread"

  reply=$(chat "$aid" "$tid" "hello from $tag" 2>"$TEST_TMP/chat.err" || true)
  assert_contains "agent replies over the chat WebSocket via the provider" "agent reached the provider" "$reply"
  hist=$(api GET "/api/agents/$aid/threads/$tid/history")
  assert_contains "the user turn is stored in thread history" "hello from $tag" "$hist"
  assert_contains "the assistant turn is stored in thread history" "agent reached the provider" "$hist"
}
