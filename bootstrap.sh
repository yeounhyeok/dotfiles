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
KEYS=(DEEPSEEK_API_KEY OPENROUTER_API_KEY)   # keys to pull if present
KEYS_ENV="$HOME/.config/opencode/keys.env"
SESSION_FILE="$HOME/.config/opencode/bw_session"

say(){ printf '\033[1;36m>>\033[0m %s\n' "$*"; }

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

# 3) point bw at self-hosted server & ensure logged-in -------------------
CUR_SERVER="$(bw config server 2>/dev/null || true)"
[ "$CUR_SERVER" = "$BW_SERVER" ] || { say "pointing bw at $BW_SERVER"; bw logout >/dev/null 2>&1 || true; bw config server "$BW_SERVER" >/dev/null; }
if [ "$(bw status 2>/dev/null | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"])' 2>/dev/null)" = "unauthenticated" ]; then
  say "logging into Vaultwarden (email + master password)..."
  bw login
fi

# 4) unlock (master password ONCE) & save session -----------------------
say "unlocking vault (master password)..."
mkdir -p "$(dirname "$SESSION_FILE")"
SESSION="$(bw unlock --raw)"
printf '%s' "$SESSION" > "$SESSION_FILE"; chmod 600 "$SESSION_FILE"
export BW_SESSION="$SESSION"

# 5) pull keys from the "Hermes .env" item custom fields ----------------
say "pulling API keys from '$BW_ITEM'..."
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

say "done ✅  open a new shell (or: source $KEYS_ENV) then run: opencode"
