#!/usr/bin/env bash
# Launcher PID lifecycle against a mocked proxy process:
# not-running -> start -> idempotent start -> stop -> stale-PID cleanup.
set -uo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "test_pid_lifecycle: start/stop/status against a mocked proxy"

export GLM_CLAUDE_HOME="$TEST_TMP/home"
mkdir -p "$GLM_CLAUDE_HOME"
port="$(pick_port)"
printf 'PROXY_PORT="%s"\n' "$port" >"$GLM_CLAUDE_HOME/config.env"
export NVIDIA_API_KEY="lifecycle-test-key"
export GLM_CLAUDE_PROXY_CMD="python3 '$TESTS_DIR/mock_proxy.py' $port"
export NO_COLOR=1

pid_file="$GLM_CLAUDE_HOME/proxy.pid"

out="$(bash "$LAUNCHER" status 2>&1)"
assert_rc 1 $? "status exits 1 before start"
assert_contains "$out" "not running" "status reports not running"

out="$(bash "$LAUNCHER" start 2>&1)"
assert_rc 0 $? "start succeeds"
assert_contains "$out" "healthy" "start reports healthy"
assert_file "$pid_file" "PID file created"
assert_mode 600 "$GLM_CLAUDE_HOME/litellm.yaml" "regenerated litellm.yaml is mode 600"

out="$(bash "$LAUNCHER" start 2>&1)"
assert_rc 0 $? "second start is a no-op success"
assert_contains "$out" "already running" "second start says already running"

out="$(bash "$LAUNCHER" status 2>&1)"
assert_rc 0 $? "status exits 0 while running"
assert_contains "$out" "running (pid" "status reports the pid"

out="$(bash "$LAUNCHER" stop 2>&1)"
assert_rc 0 $? "stop succeeds"
assert_contains "$out" "stopped" "stop reports stopped"
assert_no_file "$pid_file" "PID file removed on stop"

out="$(bash "$LAUNCHER" status 2>&1)"
assert_rc 1 $? "status exits 1 after stop"

out="$(bash "$LAUNCHER" stop 2>&1)"
assert_rc 0 $? "stop when not running is a no-op success"
assert_contains "$out" "not running" "stop reports not running"

# Stale PID file: points at a dead process, must be cleaned up.
bash -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null || true
echo "$dead_pid" >"$pid_file"
out="$(bash "$LAUNCHER" status 2>&1)"
assert_rc 1 $? "status with stale PID exits 1"
assert_contains "$out" "stale" "stale PID file is reported"
assert_no_file "$pid_file" "stale PID file is removed"

# restart cycles the process.
out="$(bash "$LAUNCHER" restart 2>&1)"
assert_rc 0 $? "restart from stopped state succeeds"
pid_before="$(cat "$pid_file")"
out="$(bash "$LAUNCHER" restart 2>&1)"
assert_rc 0 $? "restart while running succeeds"
pid_after="$(cat "$pid_file")"
if [ "$pid_before" != "$pid_after" ]; then
  t_pass "restart spawned a new process"
else
  t_fail "restart spawned a new process (pid unchanged: $pid_before)"
fi

bash "$LAUNCHER" stop >/dev/null 2>&1

finish_test
