#!/usr/bin/env bash
# One-shot bootstrap for a new machine:
#   - installs opencode (if missing)
#   - installs Bitwarden CLI (if missing)
#   - unlocks Vaultwarden ONCE (master password prompt), pulls API keys
#   - wires keys into the shell + links the opencode config
#
# Usage (the ONE line you run on any new device):
#   git clone <this-repo> ~/dotfiles && ~/dotfiles/bootstrap.sh
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BW_SERVER="https://vault.yeoun.org"
BW_ITEM="Hermes .env"                 # single source of truth (custom fields = keys)
KEYS=(OLLAMA_API_KEY DEEPSEEK_API_KEY OPENROUTER_API_KEY OBSIDIAN_MCP_TOKEN)   # keys to pull if present
KEYS_ENV="$HOME/.config/opencode/keys.env"
SESSION_FILE="$HOME/.config/opencode/bw_session"

say(){ printf '\033[1;36m>>\033[0m %s\n' "$*"; }
bw_status(){ bw status ${1:+--session "$1"} 2>/dev/null \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true; }

# 1) opencode ------------------------------------------------------------
if ! command -v opencode >/dev/null 2>&1; then
  say "installing opencode..."
  curl -fsSL https://opencode.ai/install | bash
  export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"
fi

# 2) bitwarden cli -------------------------------------------------------
if ! command -v bw >/dev/null 2>&1; then
  say "installing bitwarden-cli..."
  npm install -g @bitwarden/cli >/dev/null 2>&1 || {
    echo "!! npm not found — install Node/npm then re-run, or install bw manually"; exit 1; }
fi

# 3) point bw at the self-hosted server ---------------------------------
CUR_SERVER="$(bw config server 2>/dev/null || true)"
[ "$CUR_SERVER" = "$BW_SERVER" ] || {
  say "pointing bw at $BW_SERVER"
  bw logout >/dev/null 2>&1 || true
  bw config server "$BW_SERVER" >/dev/null
}

# 4) get a session — master password is typed AT MOST ONCE ---------------
# Order: reuse a still-valid saved session -> login --raw -> unlock --raw.
# `bw login --raw` already returns an UNLOCKED session, so calling `bw unlock`
# afterwards is what made the old script ask for the password twice.
mkdir -p "$(dirname "$SESSION_FILE")"
SESSION=""

if [ -s "$SESSION_FILE" ]; then
  CANDIDATE="$(cat "$SESSION_FILE")"
  if [ "$(bw_status "$CANDIDATE")" = "unlocked" ]; then
    SESSION="$CANDIDATE"
    say "reusing saved vault session (no password needed)"
  fi
fi

if [ -z "$SESSION" ]; then
  case "$(bw_status)" in
    unauthenticated)
      say "logging into Vaultwarden (email + master password — ONCE)..."
      SESSION="$(bw login --raw)" ;;
    *)
      say "unlocking vault (master password — ONCE)..."
      SESSION="$(bw unlock --raw)" ;;
  esac
fi

[ -n "$SESSION" ] || { echo "!! could not obtain a vault session"; exit 1; }
printf '%s' "$SESSION" > "$SESSION_FILE"; chmod 600 "$SESSION_FILE"
export BW_SESSION="$SESSION"

# 5) pull keys from the "Hermes .env" item custom fields ----------------
say "pulling API keys from '$BW_ITEM'..."
# Sync first so newly-added vault fields are visible to this session
bw sync --session "$SESSION" >/dev/null 2>&1 || true
umask 077; : > "$KEYS_ENV"
ITEM_JSON="$(bw get item "$BW_ITEM" --session "$SESSION")"
for k in "${KEYS[@]}"; do
  v="$(printf '%s' "$ITEM_JSON" | python3 -c "import sys,json;f={x['name']:x.get('value','') for x in (json.load(sys.stdin).get('fields') or [])};print(f.get('$k',''))")"
  if [ -n "$v" ]; then printf 'export %s=%q\n' "$k" "$v" >> "$KEYS_ENV"; say "  ✓ $k"; else say "  – $k (not in vault yet)"; fi
done
chmod 600 "$KEYS_ENV"

# 6) source keys from shell profile (idempotent) ------------------------
PROFILE="$HOME/.zshrc"; [ -n "${BASH_VERSION:-}" ] && [ ! -f "$PROFILE" ] && PROFILE="$HOME/.bashrc"
MARK="# >>> opencode keys >>>"
grep -qF "$MARK" "$PROFILE" 2>/dev/null || cat >> "$PROFILE" <<EOF
$MARK
[ -f "$KEYS_ENV" ] && source "$KEYS_ENV"
# <<< opencode keys <<<
EOF

# 7) link opencode config -----------------------------------------------
mkdir -p "$HOME/.config/opencode"
ln -sf "$DOTFILES/.config/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
ln -sf "$DOTFILES/.config/opencode/tui.json"     "$HOME/.config/opencode/tui.json"

# 8) codex + GLM (companion script, reuses the vault session above) --------
if [ -x "$DOTFILES/bootstrap-codex.sh" ]; then
  say "wiring Codex + GLM..."
  "$DOTFILES/bootstrap-codex.sh" || say "(codex bootstrap had issues — run ~/dotfiles/bootstrap-codex.sh manually)"
fi

say "done ✅  open a new shell (or: source $KEYS_ENV) then run: opencode"
