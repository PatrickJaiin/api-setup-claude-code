# glm-claude

Use **Claude Code** with models served from **NVIDIA NIM** (GLM, Kimi, DeepSeek, …).

Claude Code only speaks the Anthropic API; NIM only speaks the OpenAI API. glm-claude
runs a local translation proxy ([claude-code-proxy](https://github.com/fuergaosi233/claude-code-proxy))
between them:

```
claude ──▶ local proxy :8082 ──▶ https://integrate.api.nvidia.com/v1
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/api-setup-claude-code/main/install.sh | bash
```

Needs `git`, `curl`, `python3` ≥ 3.10, and the `claude` CLI. It asks for your
NVIDIA API key ([build.nvidia.com](https://build.nvidia.com)) unless
`$NVIDIA_API_KEY` is exported. Everything installs under `~/.glm-claude/`.
Safe to re-run anytime.

## Use

```sh
glm-claude                # Claude Code, but on the NIM model
glm-claude -p "2+2?"      # headless — any claude args pass through
glm-claude doctor         # smoke-test the whole chain
```

The proxy stays running in the background. Manage it:
`glm-claude start | stop | restart | status | logs`.

> The UI still shows Claude model names (`/model`, status line) — Claude Code
> never knows the backend changed; the proxy rewrites model names. Check
> `/status` → `Anthropic base URL: http://127.0.0.1:8082` to confirm you're
> on the proxy.

## Change model

```sh
echo 'GLM_MODEL="moonshotai/kimi-k2.6"' > ~/.glm-claude/config.env
glm-claude restart
```

Any model on NIM works (`curl -s https://integrate.api.nvidia.com/v1/models -H "authorization: Bearer $KEY"`).
More tunables (port, token limit, timeouts): see `config.env.example`.

## Rotate key

```sh
rm ~/.glm-claude/nvidia.key && ./install.sh    # prompts for the new key
```

## Uninstall

```sh
glm-claude stop
rm -rf ~/.glm-claude ~/.local/bin/glm-claude
```

Your normal `claude` is untouched — glm-claude only sets env vars for the
sessions it launches.

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Stuck on "thinking" for minutes | That model's queue on NIM's free tier is swamped (varies by hour). Switch to a less busy model (see **Change model**) or retry off-peak. Verify with a direct `curl` to NIM — it's not the proxy. |
| Proxy won't start | Port 8082 in use (`lsof -i :8082`). Set `PROXY_PORT` in `config.env`, `glm-claude restart`. Failed starts print the last 20 log lines. |
| `422 ... "Input should be 'user' or 'assistant'"` | Upstream proxy bug with newer Claude Code; the installer patches it. Re-run `./install.sh`, then `glm-claude restart`. |
| Tool calls failing | `glm-claude logs` — look for tool_use conversion errors. Raise `MAX_TOKENS_LIMIT` in `config.env` if output is truncated (default 16384). |
| "claude.ai connectors are disabled" warning | Expected — glm-claude sets `ANTHROPIC_API_KEY` so requests go to the proxy. Harmless. |
| Why not `ANTHROPIC_MODEL="z-ai/glm-5.2"`? | Claude Code can't handle `/` in model names. Mapping happens in the proxy (`BIG/MIDDLE/SMALL_MODEL`) instead. |

## Development

```sh
make test          # plain-bash test suite
make shellcheck    # lint
make clean         # remove ~/.glm-claude (asks first)
```
