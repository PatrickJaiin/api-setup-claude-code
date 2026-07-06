#!/usr/bin/env bash
# install.sh must write a correct, locked-down proxy .env and key file,
# install the launcher, and never leak the API key to output.
set -uo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "test_env_generation: .env generation contents"

stub_dir="$TEST_TMP/stubs"
home="$TEST_TMP/home"
bin_dir="$TEST_TMP/bin"
secret="nvapi-SECRET-abc123"
make_install_stubs "$stub_dir"

out="$(PATH="$stub_dir:/usr/bin:/bin" NO_COLOR=1 \
  GLM_CLAUDE_HOME="$home" GLM_CLAUDE_BIN_DIR="$bin_dir" \
  NVIDIA_API_KEY="$secret" bash "$INSTALLER" 2>&1)"
rc=$?
assert_rc 0 "$rc" "install.sh succeeds"
assert_not_contains "$out" "$secret" "API key never appears in output"
assert_contains "$out" "glm-claude doctor" "prints next steps"

env_file="$home/claude-code-proxy/.env"
assert_file "$env_file" ".env was written"
env_content="$(cat "$env_file")"
assert_contains "$env_content" "OPENAI_API_KEY=\"$secret\"" ".env carries the NVIDIA key"
assert_contains "$env_content" 'OPENAI_BASE_URL="https://integrate.api.nvidia.com/v1"' ".env points at NIM"
assert_contains "$env_content" 'BIG_MODEL="z-ai/glm-5.2"' ".env maps BIG_MODEL"
assert_contains "$env_content" 'MIDDLE_MODEL="z-ai/glm-5.2"' ".env maps MIDDLE_MODEL"
assert_contains "$env_content" 'SMALL_MODEL="z-ai/glm-5.2"' ".env maps SMALL_MODEL"
assert_contains "$env_content" 'HOST="127.0.0.1"' ".env binds localhost"
assert_contains "$env_content" 'PORT="8082"' ".env sets the port"
assert_contains "$env_content" 'LOG_LEVEL="WARNING"' ".env sets log level"
assert_contains "$env_content" 'MAX_TOKENS_LIMIT="16384"' ".env raises the token limit"
assert_contains "$env_content" 'REQUEST_TIMEOUT="300"' ".env sets the request timeout"
assert_mode 600 "$env_file" ".env is mode 600"

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

# A config.env override must flow into the regenerated .env on reinstall.
mkdir -p "$home"
printf 'GLM_MODEL="test/other-model"\nPROXY_PORT="9999"\n' >"$home/config.env"
out="$(PATH="$stub_dir:/usr/bin:/bin" NO_COLOR=1 \
  GLM_CLAUDE_HOME="$home" GLM_CLAUDE_BIN_DIR="$bin_dir" \
  NVIDIA_API_KEY="$secret" bash "$INSTALLER" 2>&1)"
assert_rc 0 $? "reinstall with config.env succeeds"
env_content="$(cat "$env_file")"
assert_contains "$env_content" 'BIG_MODEL="test/other-model"' "config.env overrides the model"
assert_contains "$env_content" 'PORT="9999"' "config.env overrides the port"

finish_test
