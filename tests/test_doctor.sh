#!/usr/bin/env bash
# `glm-claude doctor` must pass against a mocked upstream and fail cleanly
# when the proxy is down.
set -uo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "test_doctor: smoke test against mocked proxy"

export GLM_CLAUDE_HOME="$TEST_TMP/home"
mkdir -p "$GLM_CLAUDE_HOME"
port="$(pick_port)"
printf 'PROXY_PORT="%s"\n' "$port" >"$GLM_CLAUDE_HOME/config.env"
export NVIDIA_API_KEY="doctor-test-key"
export GLM_CLAUDE_PROXY_CMD="python3 '$TESTS_DIR/mock_proxy.py' $port"
export NO_COLOR=1

stub_dir="$TEST_TMP/stubs"
mkdir -p "$stub_dir"
printf '#!/bin/bash\nexit 0\n' >"$stub_dir/claude"
chmod 755 "$stub_dir/claude"

bash "$LAUNCHER" start >/dev/null 2>&1
assert_rc 0 $? "proxy starts"

out="$(PATH="$stub_dir:$PATH" bash "$LAUNCHER" doctor 2>&1)"
assert_rc 0 $? "doctor exits 0 with healthy mocked proxy"
assert_contains "$out" "claude CLI found" "doctor: claude check passes"
assert_contains "$out" "NVIDIA API key available" "doctor: key check passes"
assert_contains "$out" "proxy responding" "doctor: health check passes"
assert_contains "$out" "well-formed message" "doctor: /v1/messages round trip passes"
assert_contains "$out" "all checks passed" "doctor: overall pass"
assert_not_contains "$out" "doctor-test-key" "doctor never prints the key"

bash "$LAUNCHER" stop >/dev/null 2>&1

out="$(PATH="$stub_dir:$PATH" bash "$LAUNCHER" doctor 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  t_pass "doctor exits non-zero when proxy is down"
else
  t_fail "doctor exits non-zero when proxy is down (got rc=0)"
fi
assert_contains "$out" "proxy not running" "doctor: reports proxy down"
assert_contains "$out" "glm-claude start" "doctor: suggests the fix"

finish_test
