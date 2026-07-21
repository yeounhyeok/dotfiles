#!/usr/bin/env bash
# Register local Hermes secrets into the Vaultwarden "Hermes .env" item
# as custom fields (single source of truth). Run ON THE HERMES BOX after unlock.
#
#   export BW_SESSION="$(bw unlock --raw)"   # unlock first
#   ~/dotfiles/register-secrets.sh
#
# Adds/updates these keys (value read from ~/.hermes/.env; never printed):
set -euo pipefail
BW_ITEM="Hermes .env"
ENV_FILE="$HOME/.hermes/.env"
KEYS=(DEEPSEEK_API_KEY OPENROUTER_API_KEY)   # OPENROUTER added later when it exists

: "${BW_SESSION:?run: export BW_SESSION=\"\$(bw unlock --raw)\" first}"
[ -f "$ENV_FILE" ] || { echo "no $ENV_FILE"; exit 1; }

ITEM_ID="$(bw get item "$BW_ITEM" --session "$BW_SESSION" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')"

python3 - "$ITEM_ID" "$ENV_FILE" "${KEYS[@]}" <<'PY' | bw encode | bw edit item "$ITEM_ID" --session "$BW_SESSION" >/dev/null && echo "✅ registered to Vaultwarden '$BW_ITEM'"
import sys,json,subprocess,os,re
item_id, env_file = sys.argv[1], sys.argv[2]
want = sys.argv[3:]
# read requested keys from dotenv (values stay in-process, never echoed)
vals={}
for line in open(env_file):
    m=re.match(r'\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$', line)
    if m and m.group(1) in want:
        v=m.group(2).strip().strip('"').strip("'")
        if v: vals[m.group(1)]=v
item=json.loads(subprocess.check_output(["bw","get","item",item_id,"--session",os.environ["BW_SESSION"]]))
fields=item.get("fields") or []
byname={f.get("name"):f for f in fields}
for k in want:
    if k not in vals:            # not present locally -> skip
        continue
    if k in byname:
        byname[k]["value"]=vals[k]; byname[k]["type"]=1
    else:
        fields.append({"name":k,"value":vals[k],"type":1})
item["fields"]=fields
print(json.dumps(item))
PY
