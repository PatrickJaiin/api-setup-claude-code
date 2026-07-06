#!/usr/bin/env bash
# Default invocation must forward all args to `claude` with the proxy env
# (ANTHROPIC_BASE_URL / ANTHROPIC_API_KEY / API_TIMEOUT_MS) set.
set -uo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "test_passthrough: arg passthrough to claude"

export GLM_CLAUDE_HOME="$TEST_TMP/home"
mkdir -p "$GLM_CLAUDE_HOME"
port="$(pick_port)"
printf 'PROXY_PORT="%s"\n' "$port" >"$GLM_CLAUDE_HOME/config.env"
export NVIDIA_API_KEY="passthrough-test-key"
export GLM_CLAUDE_PROXY_CMD="python3 '$TESTS_DIR/mock_proxy.py' $port"
export NO_COLOR=1

stub_dir="$TEST_TMP/stubs"
mkdir -p "$stub_dir"
cat >"$stub_dir/claude" <<'EOS'
#!/bin/bash
printf 'ARGS:%s\n' "$*"
printf 'BASE:%s\n' "${ANTHROPIC_BASE_URL:-}"
printf 'KEY:%s\n' "${ANTHROPIC_API_KEY:-}"
printf 'TIMEOUT:%s\n' "${API_TIMEOUT_MS:-}"
EOS
chmod 755 "$stub_dir/claude"

out="$(PATH="$stub_dir:$PATH" bash "$LAUNCHER" -p "hello world" --output-format json 2>/dev/null)"
assert_rc 0 $? "launcher exits 0"
assert_contains "$out" "ARGS:-p hello world --output-format json" "all args forwarded to claude"
assert_contains "$out" "BASE:http://127.0.0.1:$port" "ANTHROPIC_BASE_URL points at the proxy"
assert_contains "$out" "KEY:proxy-local" "ANTHROPIC_API_KEY is the local placeholder"
assert_contains "$out" "TIMEOUT:600000" "API_TIMEOUT_MS is set"

# No args at all must also work (interactive launch path).
out="$(PATH="$stub_dir:$PATH" bash "$LAUNCHER" 2>/dev/null)"
assert_rc 0 $? "no-arg launch exits 0"
assert_contains "$out" "ARGS:" "claude invoked with no args"

bash "$LAUNCHER" stop >/dev/null 2>&1

finish_test
