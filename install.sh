#!/usr/bin/env bash
# install.sh — one-command setup for glm-claude: run Claude Code on GLM
# (NVIDIA NIM) through a local Anthropic<->OpenAI translation proxy.
#
#   curl -fsSL https://raw.githubusercontent.com/<you>/glm-claude/main/install.sh | bash
#   # or, from a clone:
#   ./install.sh
set -euo pipefail

GLM_CLAUDE_HOME="${GLM_CLAUDE_HOME:-$HOME/.glm-claude}"
PROXY_DIR="$GLM_CLAUDE_HOME/claude-code-proxy"
VENV_DIR="$GLM_CLAUDE_HOME/venv"
KEY_FILE="$GLM_CLAUDE_HOME/nvidia.key"
CONFIG_FILE="$GLM_CLAUDE_HOME/config.env"
ENV_FILE="$PROXY_DIR/.env"
BIN_DIR="${GLM_CLAUDE_BIN_DIR:-$HOME/.local/bin}"

PROXY_REPO_URL="${GLM_CLAUDE_PROXY_REPO:-https://github.com/fuergaosi233/claude-code-proxy.git}"
# Raw URL of this project, used to fetch the launcher when install.sh is
# piped from curl rather than run from a clone.
RAW_URL="${GLM_CLAUDE_RAW_URL:-https://raw.githubusercontent.com/shivg/glm-claude/main}"

# --- defaults; override in ~/.glm-claude/config.env (see config.env.example) ---
GLM_MODEL="z-ai/glm-5.2"
OPENAI_BASE_URL="https://integrate.api.nvidia.com/v1"
PROXY_HOST="127.0.0.1"
PROXY_PORT="8082"
PROXY_LOG_LEVEL="WARNING"
MAX_TOKENS_LIMIT="16384"
REQUEST_TIMEOUT="300"
BIG_MODEL=""
MIDDLE_MODEL=""
SMALL_MODEL=""

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
fi

BIG_MODEL="${BIG_MODEL:-$GLM_MODEL}"
MIDDLE_MODEL="${MIDDLE_MODEL:-$GLM_MODEL}"
SMALL_MODEL="${SMALL_MODEL:-$GLM_MODEL}"

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

check_prereqs() {
  local missing=0 c
  for c in git curl python3; do
    if need_cmd "$c"; then
      ok "found $c"
    else
      err "missing prerequisite: $c"
      missing=1
    fi
  done
  if need_cmd python3; then
    if python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
      ok "python3 is >= 3.10 ($(python3 --version 2>&1))"
    else
      err "python3 >= 3.10 required, found: $(python3 --version 2>&1)"
      missing=1
    fi
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

fetch_proxy() {
  if [ -d "$PROXY_DIR/.git" ]; then
    info "updating claude-code-proxy ..."
    if git -C "$PROXY_DIR" pull --ff-only --quiet; then
      ok "proxy updated"
    else
      warn "could not update proxy (offline or diverged) — keeping existing checkout"
    fi
  else
    info "cloning claude-code-proxy ..."
    git clone --depth 1 --quiet "$PROXY_REPO_URL" "$PROXY_DIR"
    ok "proxy cloned to $PROXY_DIR"
  fi
  if [ ! -f "$PROXY_DIR/requirements.txt" ]; then
    err "proxy checkout looks broken: $PROXY_DIR/requirements.txt not found"
    exit 1
  fi
}

setup_venv() {
  if [ ! -x "$VENV_DIR/bin/pip" ]; then
    info "creating python venv ..."
    python3 -m venv "$VENV_DIR"
  fi
  info "installing proxy dependencies (quiet) ..."
  if "$VENV_DIR/bin/pip" install --quiet --disable-pip-version-check -r "$PROXY_DIR/requirements.txt"; then
    ok "dependencies installed"
  else
    if [ -f "$ENV_FILE" ] || [ -d "$VENV_DIR/lib" ]; then
      warn "pip install failed (offline?) — continuing with previously installed packages"
    else
      err "pip install failed and no previous install exists"
      exit 1
    fi
  fi
}

obtain_key() {
  if [ -n "${NVIDIA_API_KEY:-}" ]; then
    API_KEY="$NVIDIA_API_KEY"
    info "using NVIDIA API key from \$NVIDIA_API_KEY"
  elif [ -f "$KEY_FILE" ]; then
    API_KEY="$(cat "$KEY_FILE")"
    info "using NVIDIA API key from $KEY_FILE"
  else
    local tty_dev="/dev/tty"
    if [ ! -r "$tty_dev" ]; then
      err "no NVIDIA API key: export NVIDIA_API_KEY and re-run (no TTY to prompt on)"
      exit 1
    fi
    printf '%s[glm-claude install]%s Enter your NVIDIA API key (input hidden, from https://build.nvidia.com): ' "$C_BLUE" "$C_RESET" >&2
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

write_env() {
  (
    umask 077
    cat >"$ENV_FILE" <<EOF
OPENAI_API_KEY="$API_KEY"
OPENAI_BASE_URL="$OPENAI_BASE_URL"
BIG_MODEL="$BIG_MODEL"
MIDDLE_MODEL="$MIDDLE_MODEL"
SMALL_MODEL="$SMALL_MODEL"
HOST="$PROXY_HOST"
PORT="$PROXY_PORT"
LOG_LEVEL="$PROXY_LOG_LEVEL"
MAX_TOKENS_LIMIT="$MAX_TOKENS_LIMIT"
REQUEST_TIMEOUT="$REQUEST_TIMEOUT"
EOF
  )
  chmod 600 "$ENV_FILE"
  ok "proxy .env written ($ENV_FILE, mode 600)"
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
  fetch_proxy
  setup_venv
  obtain_key
  write_env
  install_launcher

  printf '\n' >&2
  ok "install complete"
  cat >&2 <<EOF

Next steps:

  glm-claude doctor    # verify the proxy + NIM round trip
  glm-claude           # launch Claude Code on $GLM_MODEL

Config lives in ~/.glm-claude/config.env (see config.env.example).
EOF
}

main "$@"
