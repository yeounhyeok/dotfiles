# One-shot bootstrap for Antigravity CLI (agy) on Windows (PowerShell).
# Companion to bootstrap-agy.sh (Linux/WSL).
#
#   git clone <this-repo> $env:USERPROFILE\dotfiles
#   & "$env:USERPROFILE\dotfiles\bootstrap-agy.ps1"
#
# What it wires up:
#   - installs agy via official install script (if missing)
#   - writes %USERPROFILE%\.gemini\antigravity-cli\settings.json with trustedWorkspaces
#   - configures bypass-permission as default via PowerShell profile alias
#   - connects obsidian-vault MCP server (header token auth, no OAuth browser flow)
#   - ensures OBSIDIAN_MCP_TOKEN is available (reuses Vaultwarden pull)
#
# Auth note: agy authenticates via Google Sign-In (browser).
#   This script does NOT handle Google login — run `agy` once to authenticate.
#   This script only handles local config + MCP wiring.

$ErrorActionPreference = "Stop"

$Dotfiles = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgyDir = Join-Path $env:USERPROFILE ".gemini\antigravity-cli"
$AgySettings = Join-Path $AgyDir "settings.json"
$KeysEnv = Join-Path $env:USERPROFILE ".config\opencode\keys.env"
$BwSessionFile = Join-Path $env:USERPROFILE ".config\opencode\bw_session"
$BwServer = "https://vault.yeoun.org"
$BwItem = "Hermes .env"

function Say($msg) { Write-Host ">> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "!! $msg" -ForegroundColor Red; exit 1 }

# Write UTF-8 without BOM (PowerShell 5.x Set-Content -Encoding UTF8 adds BOM)
function Write-Utf8NoBom($Path, $Content) {
    $Utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

# 1) agy ----------------------------------------------------------------
$AgyBin = Join-Path $env:USERPROFILE ".local\bin\agy.exe"
# Also check if agy is in PATH (installed elsewhere)
$AgyInPath = $null
try { $AgyInPath = Get-Command agy -ErrorAction Stop } catch {}

if ($AgyInPath) {
    Say "agy already installed at $($AgyInPath.Source)"
} elseif (Test-Path $AgyBin) {
    Say "agy already installed at $AgyBin"
    # Ensure ~/.local/bin is in PATH for this session
    $LocalBin = Join-Path $env:USERPROFILE ".local\bin"
    if ($env:PATH -notlike "*$LocalBin*") {
        $env:PATH = "$LocalBin;$env:PATH"
    }
} else {
    Say "installing agy via official install script..."
    # On Windows, download the install script and run via bash (WSL) or use direct binary download
    $InstallUrl = "https://antigravity.google/cli/install.sh"
    try {
        $ScriptContent = (Invoke-WebRequest -UseBasicParsing $InstallUrl).Content
        $ScriptContent | bash 2>$null
    } catch {
        # Fallback: try npm install if available, or manual download
        Say "install script failed, trying npm..."
        try {
            npm install -g @anthropic-ai/antigravity-cli 2>$null
        } catch {
            Fail "agy install failed. Try manually: curl -fsSL https://antigravity.google/cli/install.sh | bash (via WSL) or download from https://antigravity.google/cli"
        }
    }
}

# Refresh PATH
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "User") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
if (Test-Path "$env:USERPROFILE\.local\bin") {
    $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
}

# Get agy version
try {
    $AgyVersion = & agy --version 2>&1 | Select-Object -First 1
    Say "agy: $AgyVersion"
} catch {
    Say "agy: version check skipped (may need new shell)"
}

# 1b) bitwarden cli (needed for OBSIDIAN_MCP_TOKEN) ---------------------
$BwInstalled = $null
try { $BwInstalled = Get-Command bw -ErrorAction Stop } catch {}

if (-not $BwInstalled) {
    Say "installing bitwarden-cli..."
    try {
        npm install -g @bitwarden/cli 2>$null
        # npm global bin on Windows is typically %APPDATA%\npm
        $NpmBin = Join-Path $env:APPDATA "npm"
        if (Test-Path $NpmBin) {
            $env:PATH = "$NpmBin;$env:PATH"
        }
    } catch {
        Say "npm not found - install Node/npm then re-run, or set OBSIDIAN_MCP_TOKEN manually"
    }
}

# 1c) point bw at self-hosted server ----------------------------------
try {
    $CurServer = bw config server 2>$null
    if ($CurServer -ne $BwServer) {
        Say "pointing bw at $BwServer"
        try { bw logout 2>$null } catch {}
        bw config server $BwServer 2>$null
    }
} catch {
    # bw not available, skip
}

# 1d) get a vault session (reuse saved, or login/unlock) ----------------
$SessionDir = Split-Path $BwSessionFile -Parent
if (-not (Test-Path $SessionDir)) { New-Item -ItemType Directory -Path $SessionDir -Force | Out-Null }

$Session = ""

if (Test-Path $BwSessionFile) {
    $Candidate = Get-Content $BwSessionFile -Raw
    if ($Candidate) {
        try {
            $Status = bw status --session $Candidate 2>$null | ConvertFrom-Json
            if ($Status.status -eq "unlocked") {
                $Session = $Candidate
                Say "reusing saved vault session (no password needed)"
            }
        } catch {}
    }
}

if (-not $Session) {
    try { $BwCmd = Get-Command bw -ErrorAction Stop } catch {}
    if ($BwCmd) {
        try {
            $StatusRaw = bw status 2>$null
            $StatusJson = $StatusRaw | ConvertFrom-Json
            $StatusStr = $StatusJson.status
        } catch { $StatusStr = "unauthenticated" }

        switch ($StatusStr) {
            "unauthenticated" {
                Say "logging into Vaultwarden (email + master password - ONCE)..."
                $Session = bw login --raw
            }
            default {
                Say "unlocking vault (master password - ONCE)..."
                $Session = bw unlock --raw
            }
        }

        if ($Session) {
            Set-Content -Path $BwSessionFile -Value $Session -NoNewline
            # Protect file
            icacls $BwSessionFile /inheritance:r /grant:r "$($env:USERNAME):(R,W)" 2>$null | Out-Null
            $env:BW_SESSION = $Session
        }
    }
}

# 2) settings.json -- trustedWorkspaces + dark theme --------------------
if (-not (Test-Path $AgyDir)) { New-Item -ItemType Directory -Path $AgyDir -Force | Out-Null }

$HomePath = $env:USERPROFILE

if (Test-Path $AgySettings) {
    Say "settings.json exists - merging trustedWorkspaces"
    try {
        $cfg = Get-Content $AgySettings -Raw | ConvertFrom-Json
    } catch { $cfg = @{} }

    if (-not $cfg.colorScheme) { $cfg | Add-Member -NotePropertyName colorScheme -NotePropertyValue "dark" -Force }
    if (-not $cfg.trustedWorkspaces) {
        $cfg | Add-Member -NotePropertyName trustedWorkspaces -NotePropertyValue @() -Force
    }
    if ($cfg.trustedWorkspaces -notcontains $HomePath) {
        $cfg.trustedWorkspaces += $HomePath
    }

    $cfg | ConvertTo-Json -Depth 10 | ForEach-Object { Write-Utf8NoBom $AgySettings $_ }
} else {
    Say "creating settings.json with dark theme + trustedWorkspaces"
    $cfg = @{
        colorScheme = "dark"
        trustedWorkspaces = @($HomePath)
    }
    $cfg | ConvertTo-Json -Depth 10 | ForEach-Object { Write-Utf8NoBom $AgySettings $_ }
}

Say "  + settings.json configured (dark theme, ~\trusted)"

# 3) PowerShell profile alias -- bypass permissions + accept-edits ------
$ProfilePath = $PROFILE.CurrentUserAllHosts
$ProfileDir = Split-Path $ProfilePath -Parent
if (-not (Test-Path $ProfileDir)) { New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null }

$AliasMark = "# >>> agy alias >>>"
$ProfileContent = ""
if (Test-Path $ProfilePath) { $ProfileContent = Get-Content $ProfilePath -Raw }

if ($ProfileContent -notmatch [regex]::Escape($AliasMark)) {
    $AliasBlock = @"

$AliasMark
# agy with auto-approve: skip all permission prompts + accept file edits
function agy { agy.exe --dangerously-skip-permissions --mode=accept-edits @args }
# raw agy without auto-approve (for manual control)
function agy-raw { agy.exe @args }
# <<< agy alias <<<
"@
    Add-Content -Path $ProfilePath -Value $AliasBlock
    Say "  + PowerShell alias added to $ProfilePath (agy = bypass + accept-edits)"
} else {
    Say "  - agy alias already in $ProfilePath (skip)"
}

# 4) ensure OBSIDIAN_MCP_TOKEN is available ----------------------------
function HaveToken {
    if ($env:OBSIDIAN_MCP_TOKEN) { return $true }
    if (Test-Path $KeysEnv) {
        $content = Get-Content $KeysEnv -Raw
        if ($content -match "OBSIDIAN_MCP_TOKEN") { return $true }
    }
    return $false
}

if (HaveToken) {
    Say "OBSIDIAN_MCP_TOKEN available (keys.env / env)"
} else {
    Say "OBSIDIAN_MCP_TOKEN missing - pulling from Vaultwarden..."
    if (-not (Test-Path $BwSessionFile)) {
        Fail "no saved vault session. Run bootstrap.sh first, or: `$BW_SESSION = bw unlock --raw"
    }
    $Session = Get-Content $BwSessionFile -Raw
    try {
        $ItemJson = bw get item $BwItem --session $Session 2>$null
        $Item = $ItemJson | ConvertFrom-Json
        $Token = ($Item.fields | Where-Object { $_.name -eq "OBSIDIAN_MCP_TOKEN" }).value
    } catch { $Token = $null }

    if ($Token) {
        # Append to keys.env
        $KeysDir = Split-Path $KeysEnv -Parent
        if (-not (Test-Path $KeysDir)) { New-Item -ItemType Directory -Path $KeysDir -Force | Out-Null }
        $Line = "export OBSIDIAN_MCP_TOKEN=$Token"
        if (-not (Test-Path $KeysEnv)) {
            Write-Utf8NoBom $KeysEnv $Line
        } elseif (-not ((Get-Content $KeysEnv -Raw) -match "OBSIDIAN_MCP_TOKEN")) {
            Add-Content -Path $KeysEnv -Value $Line -Encoding UTF8
        }
        icacls $KeysEnv /inheritance:r /grant:r "$($env:USERNAME):(R,W)" 2>$null | Out-Null
        $env:OBSIDIAN_MCP_TOKEN = $Token
        Say "  + OBSIDIAN_MCP_TOKEN pulled into $KeysEnv"
    } else {
        Fail "OBSIDIAN_MCP_TOKEN not found in vault item '$BwItem'. Add the token to Vaultwarden and re-run."
    }
}

# 5) load token into env for this script (for the agy mcp add command) --
if (Test-Path $KeysEnv) {
    Get-Content $KeysEnv | ForEach-Object {
        if ($_ -match "^export\s+(\w+)=(.+)$") {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], "Process")
        }
    }
}

# 6) MCP -- obsidian-vault (header token auth, no OAuth) ----------------
$McpName = "obsidian-vault"
$McpUrl = "https://obsidian-mcp.yeoun.org/mcp"

# Check if already configured
$Existing = $null
try { $Existing = agy mcp list 2>$null } catch {}

if ($Existing -and $Existing -match $McpName) {
    Say "MCP server '$McpName' already configured (skip)"
} else {
    if (-not $env:OBSIDIAN_MCP_TOKEN) {
        Fail "OBSIDIAN_MCP_TOKEN not in env - cannot configure MCP server. Run: . $KeysEnv ; & $Dotfiles\bootstrap-agy.ps1"
    }
    Say "adding MCP server '$McpName' (header token auth)..."
    agy mcp add --type http --header "Authorization: Bearer $env:OBSIDIAN_MCP_TOKEN" $McpName $McpUrl
    Say "  + MCP server '$McpName' connected"
}

# 7) verify -------------------------------------------------------------
Say "verification:"
try { Say "  agy version: $(agy --version 2>&1 | Select-Object -First 1)" } catch { Say "  agy version: (need new shell)" }
try {
    $SettingsJson = Get-Content $AgySettings -Raw | ConvertFrom-Json
    Say "  settings:    theme=$($SettingsJson.colorScheme) workspaces=$($SettingsJson.trustedWorkspaces.Count)"
} catch { Say "  settings:    parse error" }
try { Say "  MCP servers: $(agy mcp list 2>&1 | Measure-Object -Line).Lines configured" } catch { Say "  MCP servers: (check manually)" }
Say "  alias:        check with: Get-Command agy"

Say "done. Open a new PowerShell window (or: . `$PROFILE) then run: agy"
Say "   first run: agy will prompt Google Sign-In (browser)"
Say "   after auth: agy runs with bypass-permissions + accept-edits + obsidian MCP"