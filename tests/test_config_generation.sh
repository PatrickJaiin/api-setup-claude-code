#!/usr/bin/env bash
# install.sh must store the key (600) without leaking it, and the launcher
# must regenerate a correct, locked-down litellm.yaml on every start — with
# the API key kept OUT of the yaml (it travels via UPSTREAM_API_KEY env).
set -uo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "test_config_generation: install + litellm.yaml generation"

stub_dir="$TEST_TMP/stubs"
home="$TEST_TMP/home"
bin_dir="$TEST_TMP/bin"
secret="nvapi-SECRET-abc123"
make_install_stubs "$stub_dir"

# Simulate a pre-LiteLLM install: the old proxy checkout must be removed.
mkdir -p "$home/claude-code-proxy/.git"

out="$(PATH="$stub_dir:/usr/bin:/bin" NO_COLOR=1 \
  GLM_CLAUDE_HOME="$home" GLM_CLAUDE_BIN_DIR="$bin_dir" \
  NVIDIA_API_KEY="$secret" bash "$INSTALLER" 2>&1)"
rc=$?
assert_rc 0 "$rc" "install.sh succeeds"
assert_not_contains "$out" "$secret" "API key never appears in install output"
assert_contains "$out" "glm-claude doctor" "prints next steps"
assert_contains "$out" "LiteLLM" "install talks about LiteLLM"

if [ -d "$home/claude-code-proxy" ]; then
  t_fail "old claude-code-proxy checkout removed"
else
  t_pass "old claude-code-proxy checkout removed"
fi

key_file="$home/nvidia.key"
assert_file "$key_file" "key file persisted"
assert_mode 600 "$key_file" "key file is mode 600"
assert_eq "$secret" "$(cat "$key_file")" "key file holds the key"

assert_file "$home/bin/glm-claude" "launcher copied into home"
if [ -L "$bin_dir/glm-claude" ]; then
  t_pass "launcher symlinked onto PATH dir"
else
  t_fail "launcher symlinked onto PATH dir"
fi

# --- launcher start must generate litellm.yaml from the defaults ---
export GLM_CLAUDE_HOME="$home"
export NVIDIA_API_KEY="$secret"
export NO_COLOR=1
port="$(pick_port)"
printf 'PROXY_PORT="%s"\n' "$port" >"$home/config.env"
export GLM_CLAUDE_PROXY_CMD="python3 '$TESTS_DIR/mock_proxy.py' $port"

out="$(bash "$LAUNCHER" start 2>&1)"
assert_rc 0 $? "launcher start succeeds"
assert_not_contains "$out" "$secret" "API key never appears in launcher output"

yaml="$home/litellm.yaml"
assert_file "$yaml" "litellm.yaml was written"
assert_mode 600 "$yaml" "litellm.yaml is mode 600"
yaml_content="$(cat "$yaml")"
assert_not_contains "$yaml_content" "$secret" "API key is NOT in litellm.yaml"
assert_contains "$yaml_content" 'api_key: "os.environ/UPSTREAM_API_KEY"' "key is referenced via env"
assert_contains "$yaml_content" 'model_name: "*opus*"' "opus tier is mapped"
assert_contains "$yaml_content" 'model_name: "*sonnet*"' "sonnet tier is mapped"
assert_contains "$yaml_content" 'model_name: "*haiku*"' "haiku tier is mapped"
assert_contains "$yaml_content" 'model_name: "*"' "catch-all tier is mapped"
assert_contains "$yaml_content" 'model: "nvidia_nim/z-ai/glm-5.2"' "default model with nvidia_nim prefix"
assert_contains "$yaml_content" 'api_base: "https://integrate.api.nvidia.com/v1"' "points at NIM"
assert_contains "$yaml_content" 'request_timeout: 300' "sets the request timeout"
assert_contains "$yaml_content" 'drop_params: true' "drops unsupported params"

bash "$LAUNCHER" stop >/dev/null 2>&1

# --- config.env overrides must flow into the regenerated yaml on restart ---
printf 'PROXY_PORT="%s"\nGLM_MODEL="test/other-model"\nLITELLM_PROVIDER="hosted_vllm"\nREQUEST_TIMEOUT="42"\n' \
  "$port" >"$home/config.env"
out="$(bash "$LAUNCHER" start 2>&1)"
assert_rc 0 $? "restart with config.env succeeds"
yaml_content="$(cat "$yaml")"
assert_contains "$yaml_content" 'model: "hosted_vllm/test/other-model"' "config.env overrides model and provider"
assert_contains "$yaml_content" 'request_timeout: 42' "config.env overrides the timeout"

bash "$LAUNCHER" stop >/dev/null 2>&1

finish_test
