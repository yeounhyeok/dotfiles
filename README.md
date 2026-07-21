# dotfiles — opencode + secrets bootstrap

One command sets up any device with the opencode agent stack (GLM/DeepSeek tiering)
and pulls API keys from Vaultwarden. **No secrets live in this repo.**

## New machine — the one line
```bash
git clone <this-repo-url> ~/dotfiles && ~/dotfiles/bootstrap.sh
```
It installs opencode + bw, unlocks Vaultwarden **once** (master password), pulls the
API keys, wires them into your shell, and links the opencode config. Then `opencode`.

## What's here
- `.config/opencode/opencode.json` — agent config. **orchestrator = smart head, coder = cheap worker.**
  - Now (DeepSeek only): head=`deepseek-reasoner`, worker=`deepseek-chat`.
  - **August (after you get an OpenRouter key):** change `orchestrator.model` to `openrouter/z-ai/glm-5.2`
    (the ratified "GLM head + DeepSeek Flash worker" setup). Worker can stay DeepSeek or become `openrouter/deepseek/deepseek-chat`.
- `ai-infra-decisions.md` — the full decision record (loaded into opencode via `instructions`).
- `bootstrap.sh` — the one-liner above.
- `register-secrets.sh` — run on the Hermes box to push local keys into Vaultwarden's `Hermes .env` item.

## Secrets model
- **Single source of truth:** Vaultwarden `Hermes .env` item, custom fields = `KEY=value`.
- Each machine's `bootstrap.sh` pulls those into `~/.config/opencode/keys.env` (chmod 600) and sources it from your shell rc.
- To add a new key everywhere: add it to the `Hermes .env` item (or `register-secrets.sh`), then re-run `bootstrap.sh` on each machine (or just `source` after a fresh pull).

## Adding OpenRouter later
1. Get the key from openrouter.ai.
2. Add field `OPENROUTER_API_KEY` to the `Hermes .env` Vaultwarden item (or extend `register-secrets.sh`).
3. `~/dotfiles/bootstrap.sh` on each machine re-pulls it. Flip the config's head model to GLM.
