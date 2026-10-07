#!/usr/bin/env bash
# shellcheck disable=SC2015
# Live e2e against a deployed template over HTTPS.
#
#   ADMIN_PASSWORD_FILE=/path/to/pw tests/railway-smoke.sh https://<domain>
#
# MOCK_BASE_URL defaults to a mock-provider sidecar in the same Railway project
# (http://mock.railway.internal:8080/v1). Set SKIP_CHAT=1 to skip the provider/chat leg.
# Set VERIFY_ONLY=1 (with AGENT_ID and THREAD_ID) to only re-check data after a redeploy.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
APP_URL=${1:?usage: railway-smoke.sh https://<domain>}; export APP_URL
: "${ADMIN_PASSWORD_FILE:?set ADMIN_PASSWORD_FILE to a file containing the admin password}"
: "${MOCK_BASE_URL:=http://mock.railway.internal:8080/v1}"
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"
trap 'rm -rf "$TEST_TMP"' EXIT

section "edge"
wait_for_code "$APP_URL/api/health" 200 120 && pass "health over HTTPS" || die "not healthy"
assert_eq "the web app is served" "200" "$(http_code "$APP_URL/")"

section "setup-wizard API is closed"
check_setup_closed

section "authentication"
assert_eq "API requires a token" "401" "$(http_code "$APP_URL/api/agents")"
assert_eq "wrong password is rejected" "401" "$(login_code "$ADMIN_USERNAME" "wrongPassword123")"
login && pass "admin signs in with the generated password" || die "admin login failed"
assert_eq "admin language set by the bootstrap" "en" "$(api GET /api/auth/me | jq -r '.locale')"
assert_eq "the default assistant exists" "1" "$(api GET /api/agents | jq '[.[] | select(.agent_id=="main")] | length')"

if [ "${VERIFY_ONLY:-0}" = 1 ]; then
  section "data survived"
  : "${AGENT_ID:?}" "${THREAD_ID:?}"
  assert_eq "provider kept" "mock" "$(api GET /api/admin/providers | jq -r '.[0].name')"
  assert_contains "chat history kept" "hello from live" "$(api GET "/api/agents/$AGENT_ID/threads/$THREAD_ID/history")"
elif [ "${SKIP_CHAT:-0}" != 1 ]; then
  section "product flow"
  check_product_flow live
  printf 'AGENT_ID=%s THREAD_ID=%s\n' "$(<"$TEST_TMP/agent")" "$(<"$TEST_TMP/thread")"
fi

summary
