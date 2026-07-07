# glm-claude

Run **Claude Code** on non-Anthropic models using **LiteLLM** as a local
router — bring a key from any OpenAI-compatible provider (default:
**NVIDIA NIM**: GLM, DeepSeek, Kimi, Llama, …).

Claude Code only speaks the Anthropic API. LiteLLM serves that API locally
(`/v1/messages`) and routes every request to your provider with your key:

```
claude ──▶ LiteLLM router :8082 ──▶ https://integrate.api.nvidia.com/v1  (or any OpenAI-compatible API)
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/PatrickJaiin/api-setup-claude-code/main/install.sh | bash
```

Needs `curl`, `python3` 3.10–3.13 (3.12/3.13 recommended), and the `claude`
CLI. It asks for your provider API key (NVIDIA keys:
[build.nvidia.com](https://build.nvidia.com)) unless `$NVIDIA_API_KEY` is
exported. Everything installs under `~/.glm-claude/`. Safe to re-run anytime —
re-running also migrates older (pre-LiteLLM) installs; follow with
`glm-claude restart`.

## Use

```sh
glm-claude                # Claude Code, but on your provider's model
glm-claude -p "2+2?"      # headless — any claude args pass through
glm-claude doctor         # smoke-test the whole chain
```

The router stays running in the background. Manage it:
`glm-claude start | stop | restart | status | logs`.

> The UI still shows Claude model names (`/model`, status line) — Claude Code
> never knows the backend changed; the router rewrites model names
> (opus-class → `BIG_MODEL`, sonnet → `MIDDLE_MODEL`, haiku → `SMALL_MODEL`,
> anything else → `BIG_MODEL`). Check `/status` →
> `Anthropic base URL: http://127.0.0.1:8082` to confirm you're on the router.

## Change model

```sh
echo 'GLM_MODEL="deepseek-ai/deepseek-v4-flash"' > ~/.glm-claude/config.env
glm-claude restart
```

Any model on NIM works (`curl -s https://integrate.api.nvidia.com/v1/models -H "authorization: Bearer $KEY"`).
Pick one with solid **tool calling** — Claude Code is agentic. Tested on NIM:
`deepseek-ai/deepseek-v4-flash` is fast and tool-calls correctly;
`moonshotai/kimi-k2.6` currently garbles tool calls; `z-ai/glm-5.2` works but
its free-tier queue is often congested.

## Use a different provider

Any OpenAI-compatible API works — set the base URL and the LiteLLM provider
prefix, then store that provider's key:

```sh
cat > ~/.glm-claude/config.env <<'EOF'
OPENAI_BASE_URL="https://my-provider.example.com/v1"
LITELLM_PROVIDER="hosted_vllm"       # generic OpenAI-compatible; or any prefix from docs.litellm.ai/docs/providers
GLM_MODEL="my/model-name"
EOF
rm ~/.glm-claude/nvidia.key && ./install.sh   # prompts for the new key
glm-claude restart
```

More tunables (port, timeouts, per-tier models): see `config.env.example`.
The key is stored only in `~/.glm-claude/nvidia.key` (mode 600) and handed to
LiteLLM via environment — it is never written into the generated
`litellm.yaml`.

## Rotate key

```sh
rm ~/.glm-claude/nvidia.key && ./install.sh    # prompts for the new key
glm-claude restart
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
| Stuck on "thinking" for minutes | That model's queue on NIM's free tier is swamped (varies by hour). Switch to a less busy model (see **Change model**) or retry off-peak. Verify with a direct `curl` to NIM — it's not the router. |
| Router won't start | Port 8082 in use (`lsof -i :8082`). Set `PROXY_PORT` in `config.env`, `glm-claude restart`. Failed starts print the last 20 log lines. |
| `pip install` fails during install | Python 3.14 has no prebuilt wheels for LiteLLM's dependencies yet. Install Python 3.12 or 3.13 (`brew install python@3.13`) and re-run — the installer picks it up and rebuilds the venv automatically. |
| Tool calls produce gibberish | The model's tool-call template on the provider side is broken (e.g. kimi-k2.6 on NIM today). Switch models — `deepseek-ai/deepseek-v4-flash` is verified. |
| `404 ... /v1/responses` in logs | Your provider lacks OpenAI's Responses API. Don't set `LITELLM_PROVIDER="openai"`; use `hosted_vllm` (generic) or `nvidia_nim`. |
| "claude.ai connectors are disabled" warning | Expected — glm-claude sets `ANTHROPIC_API_KEY` so requests go to the router. Harmless. |
| Why not `ANTHROPIC_MODEL="z-ai/glm-5.2"`? | Claude Code can't handle `/` in model names. Mapping happens in the LiteLLM router (`GLM_MODEL` / `BIG/MIDDLE/SMALL_MODEL`) instead. |

## Development

```sh
make test          # plain-bash test suite
make shellcheck    # lint
make clean         # remove ~/.glm-claude (asks first)
```
