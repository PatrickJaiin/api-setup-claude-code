# glm-claude

Run **Claude Code** with **GLM 5.2 served from NVIDIA NIM**.

Claude Code only speaks the Anthropic Messages API (`/v1/messages`); NVIDIA NIM
(`https://integrate.api.nvidia.com/v1`) is OpenAI-compatible only. glm-claude
wires the two together by running the open-source
[claude-code-proxy](https://github.com/fuergaosi233/claude-code-proxy)
translation proxy locally, configured with NIM as its upstream, and launching
Claude Code pointed at that proxy.

```
claude  ──Anthropic /v1/messages──▶  local proxy :8082  ──OpenAI /chat/completions──▶  NVIDIA NIM
```

## Install (one command)

```sh
curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/api-setup-claude-code/main/install.sh | bash
```

Or from a clone: `./install.sh` (or `make install`).

The installer checks prerequisites (`git`, `python3` >= 3.10, `curl`, the
`claude` CLI), sets everything up under `~/.glm-claude/`, and asks for your
NVIDIA API key (get one at <https://build.nvidia.com>) — or uses
`$NVIDIA_API_KEY` if it's already exported. Re-running it is safe: it updates
the proxy, reuses your stored key, and refreshes the config.

## Quick start

```sh
glm-claude doctor          # smoke-test the whole chain (proxy + live NIM round trip)
glm-claude                 # launch Claude Code on GLM
glm-claude -p "2+2?"       # headless mode — all args pass through to claude
```

## Usage

Running `glm-claude` with no subcommand starts the proxy if it isn't running,
waits for it to become healthy, then launches `claude` with
`ANTHROPIC_BASE_URL` pointed at the proxy. Anything you'd pass to `claude`
works unchanged:

```sh
glm-claude                                   # interactive session
glm-claude -p "summarize this repo"          # headless one-shot
glm-claude -p "explain foo.py" --output-format json
glm-claude --continue                        # resume the last conversation
```

The proxy keeps running in the background between sessions, so subsequent
launches are instant. Manage it with:

| Command              | What it does                                                        |
| -------------------- | ------------------------------------------------------------------- |
| `glm-claude start`   | Start the background proxy (no-op if already running)              |
| `glm-claude stop`    | Stop the proxy and remove the PID file                              |
| `glm-claude restart` | Stop + start (picks up `config.env` changes)                        |
| `glm-claude status`  | Report state; exits 0 when running, 1 when not                      |
| `glm-claude logs`    | `tail -f` the proxy log (`~/.glm-claude/proxy.log`)                 |
| `glm-claude doctor`  | Smoke test: CLI, key, proxy health, live `/v1/messages` round trip  |
| `glm-claude help`    | Show usage                                                          |

Everything lives under `~/.glm-claude/`: the proxy checkout, python venv,
`config.env`, `nvidia.key`, `proxy.log`, and `proxy.pid`.

### Switching the model

Copy `config.env.example` to `~/.glm-claude/config.env`, set:

```sh
GLM_MODEL="some-org/some-model"
```

then run `glm-claude restart`. The proxy `.env` is regenerated from your
config on every start. Port, token limit, timeouts, and per-tier model
overrides are all in the same file.

### Rotating the API key

```sh
rm ~/.glm-claude/nvidia.key
./install.sh            # prompts for the new key (or export NVIDIA_API_KEY first)
```

The key lives only in `~/.glm-claude/nvidia.key` and the proxy's `.env`
(both mode 600); it is never committed or printed.

## Uninstall

```sh
glm-claude stop                    # stop the background proxy
make clean                         # from a clone: removes ~/.glm-claude after confirming
```

Or by hand, without a clone:

```sh
glm-claude stop
rm -rf ~/.glm-claude               # proxy checkout, venv, config, stored API key, logs
rm -f ~/.local/bin/glm-claude      # the launcher symlink
```

That removes every trace of glm-claude. Your `claude` CLI itself is untouched
and keeps working against Anthropic as before — glm-claude only sets
`ANTHROPIC_BASE_URL` for the sessions it launches, never globally.

## Troubleshooting

**Proxy won't start (port in use).** Something else owns port 8082. Find it
with `lsof -i :8082`, or move glm-claude: set `PROXY_PORT="8083"` in
`~/.glm-claude/config.env` and run `glm-claude restart`. A failed start prints
the last 20 proxy log lines automatically.

**Tool calls failing mid-session.** Run `glm-claude logs` and look for
`tool_use` conversion errors — the proxy translates Anthropic tool calls
to/from OpenAI function calls, and malformed upstream output shows up there.
Truncated tool output usually means the token cap is too low; glm-claude
already raises `MAX_TOKENS_LIMIT` to 16384 (proxy default is 4096), and you
can raise it further in `config.env`.

**Model-name gotcha (`/` in the model string).** Don't set
`ANTHROPIC_MODEL="z-ai/glm-5.2"` — Claude Code can't handle a `/` in the model
name. That's why glm-claude never sets `ANTHROPIC_MODEL` at all: the mapping
happens inside the proxy via `BIG_MODEL` / `MIDDLE_MODEL` / `SMALL_MODEL`,
so Claude Code keeps requesting its normal Anthropic model names and the proxy
rewrites them to the NIM model.

**Doctor.** `glm-claude doctor` checks: the `claude` CLI, the stored key, proxy
health over HTTP, and a real Anthropic-format `/v1/messages` request through
the proxy (this last check hits NIM and needs a valid key; in the test suite
the upstream is mocked instead).

## Development

```sh
make test          # plain-bash test suite (no bats required)
make shellcheck    # lint all scripts
make clean         # remove ~/.glm-claude (asks first)
```
