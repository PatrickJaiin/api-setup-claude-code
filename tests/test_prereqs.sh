#!/usr/bin/env bash
# install.sh must detect a missing `claude` CLI, print the npm install
# command, and exit non-zero.
set -uo pipefail
# shellcheck source=tests/helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

echo "test_prereqs: prerequisite detection"

stub_dir="$TEST_TMP/stubs"
make_install_stubs "$stub_dir"
rm -f "$stub_dir/claude" # everything present EXCEPT claude

out="$(PATH="$stub_dir" NO_COLOR=1 GLM_CLAUDE_HOME="$TEST_TMP/home" \
  /bin/bash "$INSTALLER" 2>&1)"
rc=$?
assert_rc 1 "$rc" "exits non-zero when claude is missing"
assert_contains "$out" "npm install -g @anthropic-ai/claude-code" "prints the claude install command"
assert_contains "$out" "claude" "names the missing prerequisite"

# With git also missing, it must still fail and name git.
rm -f "$stub_dir/git"
out="$(PATH="$stub_dir" NO_COLOR=1 GLM_CLAUDE_HOME="$TEST_TMP/home" \
  /bin/bash "$INSTALLER" 2>&1)"
rc=$?
assert_rc 1 "$rc" "exits non-zero when git is missing"
assert_contains "$out" "missing prerequisite: git" "names git as missing"

# With all prerequisites stubbed in, the prereq stage must pass (install
# proceeds far enough to write the key file).
make_install_stubs "$stub_dir"
out="$(PATH="$stub_dir:/usr/bin:/bin" NO_COLOR=1 \
  GLM_CLAUDE_HOME="$TEST_TMP/home2" GLM_CLAUDE_BIN_DIR="$TEST_TMP/bin2" \
  NVIDIA_API_KEY="prereq-test-key" bash "$INSTALLER" 2>&1)"
rc=$?
assert_rc 0 "$rc" "succeeds with all prerequisites present"

finish_test
