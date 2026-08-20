# dotfiles — opencode + codex + agy bootstrap

One command sets up any device with the full agent CLI stack (opencode + Codex + Antigravity CLI)
and pulls API keys from Vaultwarden. **No secrets live in this repo.**

## New machine — the one line
```bash
git clone <this-repo-url> ~/dotfiles && ~/dotfiles/bootstrap.sh
```
It installs opencode + bw, gets a Vaultwarden session (**master password at most once**),
pulls the API keys, wires them into your shell, links the opencode config, then chains into
`bootstrap-codex.sh` (Codex + GLM) and `bootstrap-agy.sh` (Antigravity CLI). Then `opencode` / `agy` / `codex`.

> **Password prompts:** a still-valid saved session at `~/.config/opencode/bw_session` is
> reused (0 prompts). Otherwise you type the master password exactly **once** —
> `bw login --raw` already returns an unlocked session, so `bw unlock` is never called after it.

## What's here
- `.config/opencode/opencode.json` — agent config.
  - **provider:** `ollama` → Ollama Cloud (`https://ollama.com/v1`, OpenAI-compatible) via
    `@ai-sdk/openai-compatible`, key from `{env:OLLAMA_API_KEY}`.
  - **head / orchestrator:** `ollama/glm-5.2` — Intelligence Index 51, GDPval 1524 (top agentic).
    **Reasoning effort = `max`** (GLM-5.2 supports High/Max thinking levels; verified against
    Ollama Cloud `/v1` 2026-07-25 via `reasoning_effort: "max"` — response separates `reasoning`
    from `content`). Configured at `provider.ollama.models.glm-5.2.options.reasoningEffort`.
    **Effort variants** (cycle with `Ctrl+T` in TUI): `low` / `medium` / `high` / `max`.
    All four verified live against Ollama Cloud `/v1` 2026-07-25. Default is `max`.
  - **worker / coder:** `ollama/kimi-k2.7-code` — code-specialised.
  - **vision:** `ollama/gemma4:31b` — see below.
  - also declared: `minimax-m3` (long context, also vision-capable), `nemotron-3-nano:30b` (cheap/fast).
  - **permission:** `edit` / `webfetch` `allow`; `bash` allows everything **except** destructive
    commands (`kill`/`pkill`/`rm -r`/`sudo`/`git push`/… → `ask`; `shutdown`/`mkfs`/`dd` → `deny`).
- `.config/opencode/tui.json` — TUI keybinds.
  - **`variant_cycle: "ctrl+t"`** — pinned explicitly (matches opencode's built-in default).
    Cycles the active model's variants — for `glm-5.2` that's the reasoning-effort ladder
    `low → medium → high → max`. Pinning it in the repo guarantees the keybind survives even
    if a future opencode release changes the default, and lets you add more keybinds here later.

### ⚠️ glm-5.2 is text-only — it cannot see images
Verified 2026-07-23: `glm-5.2` rejects image input outright
(`this model does not support image input`). `gemma4:31b`, `minimax-m3` and
`kimi-k2.7-code` do accept images.

Any task involving a screenshot, GUI capture, plot or diagram must go through the
`vision` subagent — the orchestrator gets a text description back and works from that.
The orchestrator prompt states this explicitly, because a text-only head that silently
fails to read a screenshot will improvise a workaround instead of asking for help.

The orchestrator prompt also forbids killing/restarting a running process before its
in-memory state is persisted — that combination (blind to the screen + free rein over
`kill`) is how a GUI session's unsaved work gets destroyed.
- `ai-infra-decisions.md` — decision record (loaded into opencode via `instructions`).
- `bootstrap.sh` — the one-liner above.
- `register-secrets.sh` — run on the Hermes box to push local keys into Vaultwarden's `Hermes .env` item.

## Agent harness rules (`AGENTS.md`)
`AGENTS.md` is loaded into opencode via `opencode.json` → `instructions`, so every session
runs under the same operating rules. Recent additions:
- **§12 작업 후 문서화 — YOU MUST**: after any code change, verify related docs still match
  (README, AGENTS.md, hotkey/CLI tables). The limbus-md-helper mac port was shipped with a
  Windows-only root README and an unindexed `mac/` dir — that gap is the reason this rule exists.

## MCP — Obsidian vault (auto-connected)

`opencode.json` declares a remote MCP server `obsidian-vault` pointing at
`https://obsidian-mcp.yeoun.org/mcp` with `Authorization: Bearer {env:OBSIDIAN_MCP_TOKEN}`.
OAuth auto-detection is disabled (`oauth: false`) — the `/mcp` endpoint uses header-only
auth (no browser login flow).

`bootstrap.sh` pulls `OBSIDIAN_MCP_TOKEN` from the Vaultwarden `Hermes .env` item into
`keys.env` alongside the other API keys. After `source keys.env`, the token is in the
environment and opencode connects to the Obsidian vault automatically on startup —
no manual MCP login step.

## Secrets model
- **Single source of truth:** Vaultwarden `Hermes .env` item, custom fields = `KEY=value`.
- `bootstrap.sh` pulls `OLLAMA_API_KEY`, `DEEPSEEK_API_KEY`, `OPENROUTER_API_KEY`, `OBSIDIAN_MCP_TOKEN` into
  `~/.config/opencode/keys.env` (chmod 600) and sources it from your shell rc.
- To add a key everywhere: add the field to the `Hermes .env` item (or extend `register-secrets.sh`),
  then re-run `bootstrap.sh` on each machine.

## Model choice — why Ollama Cloud
Ollama Cloud Pro ($20/mo) is the paid backend for the whole stack (it also powers the ROLEX/hermes
agent), so opencode rides the same subscription instead of adding a second bill.

Verified 2026-07-23: `glm-5.2` scores **51** on the Artificial Analysis Intelligence Index —
tied with Sonnet 4.6, 2 points behind Opus 4.6, and the best model available on Ollama
(Kimi K2.6 = 44; **K3 is not offered**). Full reasoning lives in the Obsidian note
`개발·인프라·홈랩/AI 도구 배치 전략 (2026-07)`.

To switch models, edit `model` / `agent.*.model` in `opencode.json` — any key under
`provider.ollama.models` is selectable as `ollama/<id>`.

## Antigravity CLI (`bootstrap-agy.sh`)

`bootstrap.sh` chains into `bootstrap-agy.sh` automatically, or run it standalone:
```bash
~/dotfiles/bootstrap-agy.sh
```

What it wires up:
- **installs agy** via official install script (`curl -fsSL https://antigravity.google/cli/install.sh | bash`)
- **settings.json** — dark theme + `$HOME` in `trustedWorkspaces` (so agy trusts the workspace)
- **shell alias** — `agy` → `agy --dangerously-skip-permissions --mode=accept-edits` (auto-approve all
  tool permissions + file edits, no confirmation prompts). `agy-raw` for unmodified agy.
- **obsidian-vault MCP** — connected via header token auth (`Authorization: Bearer $OBSIDIAN_MCP_TOKEN`),
  same remote MCP server as opencode. No browser OAuth flow — uses `agy mcp add --type http --header`.
- **OBSIDIAN_MCP_TOKEN** — pulled from Vaultwarden (reuses bootstrap.sh's session)

> **Auth:** agy authenticates via Google Sign-In. On first run, `agy` will prompt for login
> (browser locally, or prints an authorization URL for remote/SSH sessions). The bootstrap script
> does NOT handle Google login — it only sets up local config + MCP wiring.
>
> **Idempotent:** re-running the script skips already-configured settings, aliases, and MCP servers.
