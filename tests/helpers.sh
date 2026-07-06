# shellcheck shell=bash
# Shared plain-bash test helpers (used because bats-core may be absent).
# Each test file sources this, runs asserts, and calls finish_test.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$TESTS_DIR")"
# Used by the test files that source this helper.
# shellcheck disable=SC2034
LAUNCHER="$REPO_DIR/bin/glm-claude"
# shellcheck disable=SC2034
INSTALLER="$REPO_DIR/install.sh"

TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/glm-claude-test.XXXXXX")"

PASS_COUNT=0
FAIL_COUNT=0

t_pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '  ok   %s\n' "$1"; }
t_fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '  FAIL %s\n' "$1" >&2; }

# assert_eq <expected> <actual> <label>
assert_eq() {
  if [ "$1" = "$2" ]; then
    t_pass "$3"
  else
    t_fail "$3 (expected '$1', got '$2')"
  fi
}

# assert_contains <haystack> <needle> <label>
assert_contains() {
  case "$1" in
    *"$2"*) t_pass "$3" ;;
    *) t_fail "$3 (missing '$2' in: $(printf '%s' "$1" | head -c 300))" ;;
  esac
}

# assert_not_contains <haystack> <needle> <label>
assert_not_contains() {
  case "$1" in
    *"$2"*) t_fail "$3 (found forbidden '$2')" ;;
    *) t_pass "$3" ;;
  esac
}

# assert_rc <expected-rc> <actual-rc> <label>
assert_rc() { assert_eq "$1" "$2" "$3"; }

# assert_file <path> <label>
assert_file() {
  if [ -f "$1" ]; then t_pass "$2"; else t_fail "$2 (missing file $1)"; fi
}

# assert_no_file <path> <label>
assert_no_file() {
  if [ -f "$1" ]; then t_fail "$2 (unexpected file $1)"; else t_pass "$2"; fi
}

file_mode() {
  case "$(uname)" in
    Darwin) stat -f '%Lp' "$1" ;;
    *) stat -c '%a' "$1" ;;
  esac
}

# assert_mode <expected-octal> <path> <label>
assert_mode() {
  assert_eq "$1" "$(file_mode "$2")" "$3"
}

pick_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

# make_stub <dir> <name> <script-body...>
make_stub() {
  local dir="$1" name="$2"
  shift 2
  printf '#!/bin/bash\n%s\n' "$*" >"$dir/$name"
  chmod 755 "$dir/$name"
}

# Stubs for install.sh runs: fake git/python3/claude that satisfy the
# installer without touching the network or building a real venv.
make_install_stubs() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/git" <<'EOS'
#!/bin/bash
if [ "$1" = "clone" ]; then
  dest="${*: -1}"
  mkdir -p "$dest/.git"
  echo "fastapi" >"$dest/requirements.txt"
  echo "print('stub')" >"$dest/start_proxy.py"
fi
exit 0
EOS
  cat >"$dir/python3" <<'EOS'
#!/bin/bash
if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then
  mkdir -p "$3/bin" "$3/lib"
  printf '#!/bin/bash\nexit 0\n' >"$3/bin/pip"
  printf '#!/bin/bash\nexit 0\n' >"$3/bin/python"
  chmod 755 "$3/bin/pip" "$3/bin/python"
fi
exit 0
EOS
  printf '#!/bin/bash\nexit 0\n' >"$dir/claude"
  chmod 755 "$dir/git" "$dir/python3" "$dir/claude"
}

# Kill a proxy the launcher may have left behind and remove temp files.
cleanup_test() {
  if [ -n "${GLM_CLAUDE_HOME:-}" ] && [ -f "$GLM_CLAUDE_HOME/proxy.pid" ]; then
    kill "$(cat "$GLM_CLAUDE_HOME/proxy.pid")" 2>/dev/null || true
  fi
  rm -rf "$TEST_TMP"
}
trap cleanup_test EXIT

finish_test() {
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS_COUNT" "$FAIL_COUNT"
  [ "$FAIL_COUNT" -eq 0 ]
}
