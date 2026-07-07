#!/usr/bin/env bash
# install.sh must detect a missing `claude` CLI, print the npm install
# command, and exit non-zero — and must NOT require git (LiteLLM is
# pip-installed, nothing is cloned).
set -uo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "test_prereqs: prerequisite detection"

stub_dir="$TEST_TMP/stubs"
make_install_stubs "$stub_dir"
rm -f "$stub_dir/claude" # everything present EXCEPT claude

out="$(PATH="$stub_dir:/usr/bin:/bin" NO_COLOR=1 GLM_CLAUDE_HOME="$TEST_TMP/home" \
  /bin/bash "$INSTALLER" 2>&1 </dev/null)"
rc=$?
assert_rc 1 "$rc" "exits non-zero when claude is missing"
assert_contains "$out" "npm install -g @anthropic-ai/claude-code" "prints the claude install command"
assert_contains "$out" "claude" "names the missing prerequisite"

# With all prerequisites stubbed in — and NO git anywhere on PATH — the
# install must succeed: the LiteLLM setup needs no clone.
make_install_stubs "$stub_dir"
assert_no_file "$stub_dir/git" "no git stub exists"
out="$(PATH="$stub_dir:/usr/bin:/bin" NO_COLOR=1 \
  GLM_CLAUDE_HOME="$TEST_TMP/home2" GLM_CLAUDE_BIN_DIR="$TEST_TMP/bin2" \
  NVIDIA_API_KEY="prereq-test-key" bash "$INSTALLER" 2>&1)"
rc=$?
assert_rc 0 "$rc" "succeeds with all prerequisites present"
assert_not_contains "$out" "missing prerequisite: git" "git is not a prerequisite"

finish_test
