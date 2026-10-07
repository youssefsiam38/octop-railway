#!/usr/bin/env bash
# shellcheck disable=SC2015
# Local smoke test: build/run the combined image, then exercise the front door and the product flow.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] || [ "${SHOW_LOGS:-0}" = 1 ]; then compose logs --no-color --tail 150 || true; fi
  [ "${KEEP_STACK:-0}" = 1 ] || compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

section "start"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --quiet-pull
wait_for_code "$APP_URL/api/health" 200 && pass "health endpoint is up through the front door" || die "app never became healthy"
assert_eq "health reports the database ready" "true" "$(curl -s "$APP_URL/api/health" | jq -r '.db')"
assert_eq "the web app is served" "200" "$(http_code "$APP_URL/")"

section "setup-wizard API is closed"
check_setup_closed

section "authentication"
assert_eq "API requires a token" "401" "$(http_code "$APP_URL/api/agents")"
assert_eq "wrong password is rejected" "401" "$(login_code "$ADMIN_USERNAME" "wrongPassword123")"
login && pass "env-created admin signs in" || die "admin login failed"
me=$(api GET /api/auth/me)
assert_eq "signed in as the admin" "admin" "$(jq -r '.role' <<<"$me")"
assert_eq "admin language set by the bootstrap" "en" "$(jq -r '.locale' <<<"$me")"

section "first-run bootstrap"
for _ in $(seq 40); do
  [ "$(api GET /api/agents | jq 'length')" -ge 1 ] && break; sleep 3
done
assert_eq "the default assistant exists" "main" "$(api GET /api/agents | jq -r '.[0].agent_id')"

section "product flow"
check_product_flow smoke

summary
