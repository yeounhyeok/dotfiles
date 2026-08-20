#!/usr/bin/env bash
# One-shot bootstrap for Antigravity CLI (agy) on a new machine.
# Companion to bootstrap.sh (opencode) and bootstrap-codex.sh (codex).
#
#   git clone <this-repo> ~/dotfiles && ~/dotfiles/bootstrap.sh   # opencode + keys
#   ~/dotfiles/bootstrap-agy.sh                                   # agy only
#
# What it wires up:
#   - installs agy via official install script (if missing)
#   - writes ~/.gemini/antigravity-cli/settings.json with trustedWorkspaces
#   - configures bypass-permission as default via shell alias
#   - connects obsidian-vault MCP server (header token auth, no OAuth browser flow)
#   - ensures OBSIDIAN_MCP_TOKEN is available (reuses bootstrap.sh's Vaultwarden pull)
#
# Auth note: agy authenticates via Google Sign-In (browser or remote URL).
#   This script does NOT handle Google login — run `agy` once to authenticate.
#   This script only handles local config + MCP wiring.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGY_DIR="$HOME/.gemini/antigravity-cli"
AGY_SETTINGS="$AGY_DIR/settings.json"
KEYS_ENV="$HOME/.config/opencode/keys.env"
BW_SESSION_FILE="$HOME/.config/opencode/bw_session"
BW_SERVER="https://vault.yeoun.org"

# Ensure ~/.local/bin is in PATH (agy installs here, but it may not be in PATH yet)
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
BW_ITEM="Hermes .env"

say(){ printf '\033[1;36m>>\033[0m %s\n' "$*"; }
bw_status(){ bw status ${1:+--session "$1"} 2>/dev/null \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true; }

# 1) agy ----------------------------------------------------------------
AGY_BIN="$HOME/.local/bin/agy"
if [ -x "$AGY_BIN" ]; then
  say "agy already installed at $AGY_BIN"
else
  say "installing agy via official install script..."
  curl -fsSL https://antigravity.google/cli/install.sh | bash || {
    echo "!! agy install failed — try manually: curl -fsSL https://antigravity.google/cli/install.sh | bash"; }
fi
export PATH="$HOME/.local/bin:$PATH"
say "agy: $(agy --version 2>&1 | head -1 || echo ok)"

# 1b) bitwarden cli (needed for OBSIDIAN_MCP_TOKEN) ---------------------
if ! command -v bw >/dev/null 2>&1; then
  say "installing bitwarden-cli..."
  npm install -g @bitwarden/cli >/dev/null 2>&1 || {
    echo "!! npm not found — install Node/npm then re-run, or set OBSIDIAN_MCP_TOKEN manually"; }
  # npm global bin may not be in PATH (esp. WSL)
  NPM_BIN="$(npm config get prefix 2>/dev/null)/bin"
  [ -d "$NPM_BIN" ] && case ":$PATH:" in *":$NPM_BIN:"*) ;; *) export PATH="$NPM_BIN:$PATH";; esac
fi

# 1c) point bw at self-hosted server ----------------------------------
if command -v bw >/dev/null 2>&1; then
  CUR_SERVER="$(bw config server 2>/dev/null || true)"
  [ "$CUR_SERVER" = "$BW_SERVER" ] || {
    say "pointing bw at $BW_SERVER"
    bw logout >/dev/null 2>&1 || true
    bw config server "$BW_SERVER" >/dev/null
  }
fi

# 1d) get a vault session (reuse saved, or login/unlock) ----------------
mkdir -p "$(dirname "$BW_SESSION_FILE")"
SESSION=""

if [ -s "$BW_SESSION_FILE" ]; then
  CANDIDATE="$(cat "$BW_SESSION_FILE")"
  if [ "$(bw_status "$CANDIDATE")" = "unlocked" ]; then
    SESSION="$CANDIDATE"
    say "reusing saved vault session (no password needed)"
  fi
fi

if [ -z "$SESSION" ] && command -v bw >/dev/null 2>&1; then
  case "$(bw_status)" in
    unauthenticated)
      say "logging into Vaultwarden (email + master password — ONCE)..."
      SESSION="$(bw login --raw)" ;;
    *)
      say "unlocking vault (master password — ONCE)..."
      SESSION="$(bw unlock --raw)" ;;
  esac
fi

[ -n "$SESSION" ] && {
  printf '%s' "$SESSION" > "$BW_SESSION_FILE"; chmod 600 "$BW_SESSION_FILE"
  export BW_SESSION="$SESSION"
}

# 2) settings.json — trustedWorkspaces + dark theme --------------------
mkdir -p "$AGY_DIR"

# agy v1.1.16+ preserves unrecognized fields, but we own the whole file here.
# Only set fields we care about; preserve existing if present.
if [ -f "$AGY_SETTINGS" ]; then
  say "settings.json exists — merging trustedWorkspaces"
  python3 - "$AGY_SETTINGS" <<'PYSET'
import json, sys, os
path = sys.argv[1]
try:
    cfg = json.load(open(path))
except (json.JSONDecodeError, FileNotFoundError):
    cfg = {}
cfg.setdefault("colorScheme", "dark")
ws = cfg.setdefault("trustedWorkspaces", [])
home = os.path.expanduser("~")
if home not in ws:
    ws.append(home)
json.dump(cfg, open(path, "w"), indent=2)
PYSET
else
  say "creating settings.json with dark theme + trustedWorkspaces"
  python3 -c "
import json, os
cfg = {'colorScheme': 'dark', 'trustedWorkspaces': [os.path.expanduser('~')]}
json.dump(cfg, open('$AGY_SETTINGS', 'w'), indent=2)
"
fi
chmod 600 "$AGY_SETTINGS"
say "  + settings.json configured (dark theme, ~/trusted)"

# 3) shell alias — bypass permissions + accept-edits as default ---------
# agy doesn't have a config-file key for --dangerously-skip-permissions,
# so we wire it as a shell alias. User can still run `command agy` for raw.
PROFILE="$HOME/.zshrc"
[ -n "${BASH_VERSION:-}" ] && [ ! -f "$PROFILE" ] && PROFILE="$HOME/.bashrc"

ALIAS_MARK="# >>> agy alias >>>"
if ! grep -qF "$ALIAS_MARK" "$PROFILE" 2>/dev/null; then
  cat >> "$PROFILE" <<EOF

$ALIAS_MARK
# agy with auto-approve: skip all permission prompts + accept file edits
alias agy='agy --dangerously-skip-permissions --mode=accept-edits'
# raw agy without auto-approve (for manual control)
alias agy-raw='command agy'
# <<< agy alias <<<
EOF
  say "  + shell alias added to $PROFILE (agy = bypass + accept-edits)"
else
  say "  - agy alias already in $PROFILE (skip)"
fi

# 4) ensure OBSIDIAN_MCP_TOKEN is available ----------------------------
have_token(){
  [ -n "${OBSIDIAN_MCP_TOKEN:-}" ] && return 0
  [ -f "$KEYS_ENV" ] && grep -q 'OBSIDIAN_MCP_TOKEN' "$KEYS_ENV" 2>/dev/null && return 0
  return 1
}

if have_token; then
  say "OBSIDIAN_MCP_TOKEN available (keys.env / env)"
else
  say "OBSIDIAN_MCP_TOKEN missing — pulling from Vaultwarden..."
  if [ -s "$BW_SESSION_FILE" ]; then
    SESSION="$(cat "$BW_SESSION_FILE")"
  else
    echo "!! no saved vault session. Run ~/dotfiles/bootstrap.sh first, or: export BW_SESSION=\"\$(bw unlock --raw)\""
    echo "   (OBSIDIAN_MCP_TOKEN is needed for the obsidian-vault MCP server)"
    exit 1
  fi
  ITEM_JSON="$(bw get item "$BW_ITEM" --session "$SESSION" 2>/dev/null || true)"
  v="$(printf '%s' "$ITEM_JSON" | python3 -c "import sys,json;f={x['name']:x.get('value','') for x in (json.load(sys.stdin).get('fields') or [])};print(f.get('OBSIDIAN_MCP_TOKEN',''))" 2>/dev/null || true)"
  if [ -n "$v" ]; then
    umask 077; touch "$KEYS_ENV"
    if ! grep -q 'OBSIDIAN_MCP_TOKEN' "$KEYS_ENV" 2>/dev/null; then
      printf 'export OBSIDIAN_MCP_TOKEN=%q\n' "$v" >> "$KEYS_ENV"
    fi
    chmod 600 "$KEYS_ENV"
    export OBSIDIAN_MCP_TOKEN="$v"
    say "  + OBSIDIAN_MCP_TOKEN pulled into $KEYS_ENV"
  else
    echo "!! OBSIDIAN_MCP_TOKEN not found in vault item '$BW_ITEM'"
    echo "   (MCP server will not be configured — add the token to Vaultwarden and re-run)"
    exit 1
  fi
fi

# 5) load token into env for this script (for the agy mcp add command) --
if [ -f "$KEYS_ENV" ]; then
  set -a; . "$KEYS_ENV"; set +a
fi

# 6) MCP — obsidian-vault (header token auth, no OAuth) ----------------
MCP_NAME="obsidian-vault"
MCP_URL="https://obsidian-mcp.yeoun.org/mcp"

# Check if already configured
EXISTING="$(agy mcp list 2>/dev/null || true)"
if echo "$EXISTING" | grep -q "$MCP_NAME"; then
  say "MCP server '$MCP_NAME' already configured (skip)"
else
  if [ -z "${OBSIDIAN_MCP_TOKEN:-}" ]; then
    echo "!! OBSIDIAN_MCP_TOKEN not in env — cannot configure MCP server"
    echo "   run: source $KEYS_ENV && ~/dotfiles/bootstrap-agy.sh"
    exit 1
  fi
  say "adding MCP server '$MCP_NAME' (header token auth)..."
  agy mcp add --type http \
    --header "Authorization: Bearer $OBSIDIAN_MCP_TOKEN" \
    "$MCP_NAME" "$MCP_URL"
  say "  + MCP server '$MCP_NAME' connected"
fi

# 7) verify -------------------------------------------------------------
say "verification:"
say "  agy version: $(agy --version 2>&1 | head -1)"
SETTINGS_INFO="$(python3 -c 'import json;d=json.load(open("'"$AGY_SETTINGS"'"));print("theme=%s workspaces=%d" % (d.get("colorScheme","?"), len(d.get("trustedWorkspaces",[]))))' 2>/dev/null || echo "parse error")"
say "  settings:    $SETTINGS_INFO"
say "  MCP servers: $(agy mcp list 2>&1 | wc -l | tr -d ' ') configured"
say "  alias:        grep 'agy alias' $PROFILE (check with: type agy)"

say "done ✅  open a new shell (or: source $KEYS_ENV) then run: agy"
say "   first run: agy will prompt Google Sign-In (browser or remote URL)"
say "   after auth: agy runs with bypass-permissions + accept-edits + obsidian MCP"