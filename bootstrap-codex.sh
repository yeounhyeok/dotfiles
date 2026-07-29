#!/usr/bin/env bash
# One-shot bootstrap for Codex CLI + GLM (via Ollama Cloud) on a new machine.
# Companion to bootstrap.sh (opencode). Run after bootstrap.sh, or standalone.
#
#   git clone <this-repo> ~/dotfiles && ~/dotfiles/bootstrap.sh   # opencode + this
#   ~/dotfiles/bootstrap-codex.sh                                # codex only
#
# What it wires up:
#   - installs @openai/codex (npm) if missing
#   - copies the Ollama model catalog into ~/.codex/
#   - writes model profiles (glm-5.2 default + kimi/qwen/minimax/deepseek)
#   - merges [model_providers.ollama_cloud] into ~/.codex/config.toml
#   - ensures OLLAMA_API_KEY is exported (reuses bootstrap.sh's Vaultwarden pull)
#
# Auth note: codex reads OLLAMA_API_KEY from the environment (env_key). It does
# NOT go into auth.json (that file is for OpenAI ChatGPT login only).
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$HOME/.codex"
KEYS_ENV="$HOME/.config/opencode/keys.env"      # shared with bootstrap.sh
BW_SESSION_FILE="$HOME/.config/opencode/bw_session"
BW_ITEM="Hermes .env"

say(){ printf '\033[1;36m>>\033[0m %s\n' "$*"; }

# 1) codex --------------------------------------------------------------
if ! command -v codex >/dev/null 2>&1; then
  say "installing @openai/codex..."
  npm install -g @openai/codex >/dev/null 2>&1 || {
    echo "!! npm not found — install Node/npm then re-run"; exit 1; }
fi
say "codex: $(codex --version 2>&1 | head -1 || echo ok)"

mkdir -p "$CODEX_DIR"

# 2) model catalog ------------------------------------------------------
if [ -f "$DOTFILES/.codex/ollama-models.json" ]; then
  cp "$DOTFILES/.codex/ollama-models.json" "$CODEX_DIR/ollama-models.json"
  say "copied ollama-models.json -> $CODEX_DIR/"
else
  echo "!! $DOTFILES/.codex/ollama-models.json missing — catalog not installed"; fi

# 3) model profiles -----------------------------------------------------
# catalog path expanded to THIS machine's $HOME. --force to overwrite existing.
FORCE="${1:-}"
write_profile(){  # name  model_slug  context_window  [extra-lines...]
  local name="$1" slug="$2" ctx="$3"; shift 3
  local f="$CODEX_DIR/$name.config.toml"
  if [ -f "$f" ] && [ "$FORCE" != "--force" ]; then
    say "  - $name.config.toml exists (skip; use --force to overwrite)"; return; fi
  {
    printf 'model = "%s"\n' "$slug"
    printf 'model_provider = "ollama_cloud"\n'
    printf 'model_context_window = %s\n' "$ctx"
    printf 'model_catalog_json = "%s/ollama-models.json"\n' "$CODEX_DIR"
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$f"
  say "  + $name.config.toml"
}

say "writing model profiles..."
write_profile glm       glm-5.2         204800  'model_reasoning_effort = "high"'
write_profile kimi      kimi-k2.7-code  262144
write_profile qwen      qwen3.5:397b    262144  '# Ollama HTTP 500 for qwen3.5 when native web_search present' 'web_search = "disabled"'
write_profile minimax   minimax-m3      524288
write_profile deepseek  deepseek-v4-pro 524288
write_profile kimi-k3    kimi-k3         262144

# 3b) make GLM the default model (so bare `codex` uses GLM) -----------------
# Set/replace top-level keys: model, model_provider, model_context_window,
# model_catalog_json, model_reasoning_effort. Only touches keys before the
# first [section] so existing tables (projects, plugins, ...) stay intact.
python3 - "$CONFIG" "$CODEX_DIR" <<'PYCFG'
import re,sys
cfg, codex_dir = sys.argv[1], sys.argv[2]
lines = open(cfg).read().splitlines()
want = {
    "model": "glm-5.2",
    "model_provider": "ollama_cloud",
    "model_context_window": "204800",
    "model_catalog_json": f"{codex_dir}/ollama-models.json",
    "model_reasoning_effort": "high",
}
# split head (top-level) from first [section]
split = len(lines)
for i,l in enumerate(lines):
    if l.startswith("["):
        split = i; break
head, tail = lines[:split], lines[split:]
seen = set()
new_head = []
for l in head:
    m = re.match(r'\s*([A-Za-z_]+)\s*=', l)
    if m and m.group(1) in want:
        k = m.group(1)
        if k not in seen:
            v = want[k]
            new_head.append(f'{k} = "{v}"' if isinstance(v,str) and k!="model_context_window" else f'{k} = {v}')
            seen.add(k)
    else:
        new_head.append(l)
for k,v in want.items():
    if k not in seen:
        new_head.append(f'{k} = "{v}"' if isinstance(v,str) and k!="model_context_window" else f'{k} = {v}')
out = new_head + ([""] if tail and new_head and new_head[-1]!="" else []) + tail
open(cfg,"w").write("\n".join(out)+"\n")
PYCFG
say "default model set to glm-5.2 (bare `codex` now uses GLM)"

# 4) merge provider block into config.toml (idempotent) ----------------
CONFIG="$CODEX_DIR/config.toml"
touch "$CONFIG"
MARK_BEGIN='# >>> codex ollama_cloud provider >>>'
MARK_END='# <<< codex ollama_cloud provider <<<'
if grep -qF "$MARK_BEGIN" "$CONFIG" 2>/dev/null; then
  say "ollama_cloud provider block already present in config.toml (skip)"
else
  cat >> "$CONFIG" <<EOF

$MARK_BEGIN
# added by bootstrap-codex.sh — auth via env: OLLAMA_API_KEY
[model_providers.ollama_cloud]
name = "Ollama Cloud"
base_url = "https://ollama.com/v1"
env_key = "OLLAMA_API_KEY"
$MARK_END
EOF
  say "merged [model_providers.ollama_cloud] into config.toml"
fi

# 5) ensure OLLAMA_API_KEY is in the shell env -------------------------
have_key(){
  [ -n "${OLLAMA_API_KEY:-}" ] && return 0
  [ -f "$KEYS_ENV" ] && grep -q 'OLLAMA_API_KEY' "$KEYS_ENV" 2>/dev/null && return 0
  return 1
}
if have_key; then
  say "OLLAMA_API_KEY available (keys.env / env)"
else
  say "OLLAMA_API_KEY missing — pulling from Vaultwarden..."
  if [ -s "$BW_SESSION_FILE" ]; then
    SESSION="$(cat "$BW_SESSION_FILE")"
  else
    echo "!! no saved vault session. Run ~/dotfiles/bootstrap.sh first, or: export BW_SESSION=\"\$(bw unlock --raw)\""; exit 1
  fi
  ITEM_JSON="$(bw get item "$BW_ITEM" --session "$SESSION" 2>/dev/null || true)"
  v="$(printf '%s' "$ITEM_JSON" | python3 -c "import sys,json;f={x['name']:x.get('value','') for x in (json.load(sys.stdin).get('fields') or [])};print(f.get('OLLAMA_API_KEY',''))" 2>/dev/null || true)"
  if [ -n "$v" ]; then
    umask 077; touch "$KEYS_ENV"
    if ! grep -q 'OLLAMA_API_KEY' "$KEYS_ENV" 2>/dev/null; then
      printf 'export OLLAMA_API_KEY=%q\n' "$v" >> "$KEYS_ENV"
    fi
    chmod 600 "$KEYS_ENV"
    export OLLAMA_API_KEY="$v"
    say "  + OLLAMA_API_KEY pulled into $KEYS_ENV"
  else
    echo "!! OLLAMA_API_KEY not found in vault item '$BW_ITEM'"; exit 1; fi
fi

say "done.  run:  codex -c model=glm-5.2"
say "verify: codex --version && printf %s \"\$OLLAMA_API_KEY\" | head -c8"
