#!/usr/bin/env bash
# install.sh — one-command setup for glm-claude: run Claude Code on any
# OpenAI-compatible provider (default: NVIDIA NIM) through a local LiteLLM
# router.
#
#   curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/api-setup-claude-code/main/install.sh | bash
#   # or, from a clone:
#   ./install.sh
set -euo pipefail

GLM_CLAUDE_HOME="${GLM_CLAUDE_HOME:-$HOME/.glm-claude}"
VENV_DIR="$GLM_CLAUDE_HOME/venv"
KEY_FILE="$GLM_CLAUDE_HOME/nvidia.key"
CONFIG_FILE="$GLM_CLAUDE_HOME/config.env"
BIN_DIR="${GLM_CLAUDE_BIN_DIR:-$HOME/.local/bin}"

# Raw URL of this project, used to fetch the launcher when install.sh is
# piped from curl rather than run from a clone.
RAW_URL="${GLM_CLAUDE_RAW_URL:-https://raw.githubusercontent.com/PatrickJaiin/api-setup-claude-code/main}"

# --- defaults; override in ~/.glm-claude/config.env (see config.env.example) ---
GLM_MODEL="z-ai/glm-5.2"

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
fi

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_BLUE=$'\033[34m' C_YELLOW=$'\033[33m' C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_RESET=$'\033[0m'
else
  C_BLUE="" C_YELLOW="" C_RED="" C_GREEN="" C_RESET=""
fi
info() { printf '%s[glm-claude install]%s %s\n' "$C_BLUE" "$C_RESET" "$*" >&2; }
warn() { printf '%s[glm-claude install] warn:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
err()  { printf '%s[glm-claude install] error:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
ok()   { printf '%s[glm-claude install]%s %s✓%s %s\n' "$C_BLUE" "$C_RESET" "$C_GREEN" "$C_RESET" "$*" >&2; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# LiteLLM's dependency set (orjson in particular) has no prebuilt wheels for
# python 3.14 yet, so prefer 3.13 down to 3.10 and only fall back to a bare
# `python3` when nothing else is available.
PYTHON=""
pyver_between() { "$1" -c "import sys; raise SystemExit(0 if ($2) <= sys.version_info < ($3) else 1)" 2>/dev/null; }
find_python() {
  local c
  for c in python3.13 python3.12 python3.11 python3.10 python3; do
    if need_cmd "$c" && pyver_between "$c" "3, 10" "3, 14"; then
      PYTHON="$(command -v "$c")"
      return 0
    fi
  done
  if need_cmd python3 && pyver_between python3 "3, 10" "4, 0"; then
    PYTHON="$(command -v python3)"
    warn "only $(python3 --version 2>&1) found; LiteLLM dependencies may lack wheels for it"
    warn "if the install fails, install python 3.12 or 3.13 and re-run"
    return 0
  fi
  return 1
}

check_prereqs() {
  local missing=0
  if need_cmd curl; then
    ok "found curl"
  else
    err "missing prerequisite: curl"
    missing=1
  fi
  if find_python; then
    ok "using python at $PYTHON ($("$PYTHON" --version 2>&1))"
  else
    err "missing prerequisite: python3 (>= 3.10; 3.12 or 3.13 recommended)"
    missing=1
  fi
  if need_cmd claude; then
    ok "found claude CLI"
  else
    err "the 'claude' CLI is not installed"
    err "install it first with: npm install -g @anthropic-ai/claude-code"
    missing=1
  fi
  if [ "$missing" -ne 0 ]; then
    err "prerequisites missing — aborting"
    exit 1
  fi
}

# Earlier versions of glm-claude ran a cloned+patched claude-code-proxy;
# LiteLLM replaces it entirely.
migrate_old_layout() {
  if [ -d "$GLM_CLAUDE_HOME/claude-code-proxy" ]; then
    info "removing the old claude-code-proxy checkout (replaced by LiteLLM) ..."
    rm -rf "$GLM_CLAUDE_HOME/claude-code-proxy"
    ok "old proxy removed"
  fi
}

setup_venv() {
  # Rebuild the venv when it was created by a different interpreter version
  # (e.g. an old 3.14 venv that LiteLLM cannot install into).
  if [ -x "$VENV_DIR/bin/python" ]; then
    local have want
    have="$("$VENV_DIR/bin/python" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
    want="$("$PYTHON" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
    if [ "$have" != "$want" ]; then
      info "recreating venv (python ${have:-?} -> ${want:-?}) ..."
      rm -rf "$VENV_DIR"
    fi
  fi
  if [ ! -x "$VENV_DIR/bin/pip" ]; then
    info "creating python venv ..."
    "$PYTHON" -m venv "$VENV_DIR"
  fi
  info "installing LiteLLM (first run can take a few minutes) ..."
  if "$VENV_DIR/bin/pip" install --quiet --disable-pip-version-check 'litellm[proxy]'; then
    ok "LiteLLM installed"
  else
    if [ -x "$VENV_DIR/bin/litellm" ]; then
      warn "pip install failed (offline?) — continuing with previously installed LiteLLM"
    else
      err "pip install failed and no previous LiteLLM install exists"
      exit 1
    fi
  fi
}

obtain_key() {
  if [ -n "${NVIDIA_API_KEY:-}" ]; then
    API_KEY="$NVIDIA_API_KEY"
    info "using API key from \$NVIDIA_API_KEY"
  elif [ -n "${UPSTREAM_API_KEY:-}" ]; then
    API_KEY="$UPSTREAM_API_KEY"
    info "using API key from \$UPSTREAM_API_KEY"
  elif [ -f "$KEY_FILE" ]; then
    API_KEY="$(cat "$KEY_FILE")"
    info "using API key from $KEY_FILE"
  else
    local tty_dev="/dev/tty"
    if [ ! -r "$tty_dev" ]; then
      err "no API key: export NVIDIA_API_KEY and re-run (no TTY to prompt on)"
      exit 1
    fi
    printf '%s[glm-claude install]%s Enter your provider API key (input hidden; NVIDIA NIM keys: https://build.nvidia.com): ' "$C_BLUE" "$C_RESET" >&2
    read -rs API_KEY <"$tty_dev"
    printf '\n' >&2
    if [ -z "$API_KEY" ]; then
      err "empty API key — aborting"
      exit 1
    fi
  fi
  (
    umask 077
    printf '%s\n' "$API_KEY" >"$KEY_FILE"
  )
  chmod 600 "$KEY_FILE"
  ok "API key stored in $KEY_FILE (mode 600)"
}

install_launcher() {
  local script_dir launcher_src="" launcher_dst="$GLM_CLAUDE_HOME/bin/glm-claude"
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  if [ -n "$script_dir" ] && [ -f "$script_dir/bin/glm-claude" ]; then
    launcher_src="$script_dir/bin/glm-claude"
  fi

  mkdir -p "$GLM_CLAUDE_HOME/bin"
  if [ -n "$launcher_src" ]; then
    cp "$launcher_src" "$launcher_dst"
  else
    info "fetching launcher from $RAW_URL ..."
    if ! curl -fsSL "$RAW_URL/bin/glm-claude" -o "$launcher_dst"; then
      err "could not download the launcher — clone the repo and run ./install.sh instead"
      exit 1
    fi
  fi
  chmod 755 "$launcher_dst"

  mkdir -p "$BIN_DIR"
  ln -sf "$launcher_dst" "$BIN_DIR/glm-claude"
  ok "launcher installed: $BIN_DIR/glm-claude"

  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
      warn "$BIN_DIR is not on your PATH"
      warn "add it with:  export PATH=\"$BIN_DIR:\$PATH\"  (put this in your shell profile)"
      ;;
  esac
}

main() {
  info "installing glm-claude into $GLM_CLAUDE_HOME"
  check_prereqs
  mkdir -p "$GLM_CLAUDE_HOME"
  migrate_old_layout
  setup_venv
  obtain_key
  install_launcher

  printf '\n' >&2
  ok "install complete"
  cat >&2 <<EOF

Next steps:

  glm-claude restart   # (re)start the LiteLLM router with the new setup
  glm-claude doctor    # verify the router + provider round trip
  glm-claude           # launch Claude Code on $GLM_MODEL

Config lives in ~/.glm-claude/config.env (see config.env.example).
EOF
}

main "$@"
