#!/usr/bin/env bash
# shellcheck disable=SC2015
# Persistence: create data, recreate the container keeping the volume, verify everything survived.
set -euo pipefail
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd); export REPO_ROOT
# shellcheck source=tests/lib.sh
. "$REPO_ROOT/tests/lib.sh"

cleanup() {
  local rc=$?
  [ "$rc" -eq 0 ] || compose logs --no-color --tail 150 || true
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

section "seed"
compose down -v --remove-orphans >/dev/null 2>&1 || true
compose up -d --quiet-pull
wait_for_code "$APP_URL/api/health" 200 || die "app never became healthy"
login || die "admin login failed"
check_product_flow persist
agent=$(<"$TEST_TMP/agent"); thread=$(<"$TEST_TMP/thread")

section "recreate the container (volume kept)"
compose down --remove-orphans
compose up -d
wait_for_code "$APP_URL/api/health" 200 && pass "healthy after restart" || die "app never came back"

section "verify"
login && pass "admin still signs in" || fail "admin login after restart"
assert_eq "admin language kept" "en" "$(api GET /api/auth/me | jq -r '.locale')"
assert_eq "provider kept" "mock" "$(api GET /api/admin/providers | jq -r '.[0].name')"
assert_eq "agent kept" "1" "$(api GET /api/agents | jq --arg a "$agent" '[.[] | select(.agent_id==$a)] | length')"
assert_contains "chat history kept" "hello from persist" "$(api GET "/api/agents/$agent/threads/$thread/history")"
assert_eq "the default assistant was not duplicated" "1" "$(api GET /api/agents | jq '[.[] | select(.agent_id=="main")] | length')"
check_setup_closed

summary
