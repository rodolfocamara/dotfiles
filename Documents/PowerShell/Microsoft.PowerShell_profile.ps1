# ── Cache directory ──────────────────────────────────────────────
$_cacheDir = Join-Path $env:LOCALAPPDATA 'pwsh-cache'
if (-not (Test-Path $_cacheDir)) { [void](New-Item -ItemType Directory -Path $_cacheDir -Force) }

function _CacheInitScript {
    param([string]$Name, [string]$Exe, [scriptblock]$Generator)
    $cachePath = Join-Path $_cacheDir "$Name.ps1"
    $exePath = (Get-Command $Exe -CommandType Application -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty Source)
    if (-not $exePath) { return }
    $needsRefresh = -not (Test-Path $cachePath) -or
        (Get-Item $cachePath).LastWriteTime -lt (Get-Item $exePath).LastWriteTime
    if ($needsRefresh) { & $Generator | Set-Content $cachePath -Force }
    . $cachePath
}

# ── PSReadLine (built-in since PS 5.1, skip Get-Module scan) ───
Set-PSReadLineOption -PredictionSource HistoryAndPlugin
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Chord 'Ctrl+d' -Function DeleteCharOrExit

# ── Aliases (eza) ───────────────────────────────────────────────
if (Test-Path Alias:ls) { Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue }
function ls   { eza --git --icons --group-directories-first @args }
function ll   { eza -lh --git --icons --group-directories-first @args }
function la   { eza -lha --git --icons --group-directories-first @args }
function tree { eza --tree --icons --group-directories-first --level=2 @args }

Set-Alias grep Select-String

# ── Terminal title (cached admin check) ─────────────────────────
$global:_isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ── Starship prompt (cached init) ───────────────────────────────
_CacheInitScript -Name 'starship' -Exe 'starship' -Generator { & starship init powershell }

# Update title only when shell is idle, so apps (Claude Code, vim, ssh) keep theirs
Register-EngineEvent PowerShell.OnIdle -Action {
    $prefix = if ($global:_isAdmin) { "🛡️ " } else { "" }
    [Console]::Title = "$prefix$($PWD.Path.Replace($HOME, '~'))"
} | Out-Null

# ── k9s completion (cached) ─────────────────────────────────────
_CacheInitScript -Name 'k9s' -Exe 'k9s' -Generator { k9s completion powershell }

# ── Zoxide (cached init) ────────────────────────────────────────
$env:_ZO_DOCTOR = "0"
_CacheInitScript -Name 'zoxide' -Exe 'zoxide' -Generator { zoxide init powershell }

# ── Useful shortcuts ────────────────────────────────────────────
function mkcd { param([string]$dir) New-Item -ItemType Directory -Path $dir -Force | Out-Null; Set-Location $dir }
function which { param([string]$cmd) Get-Command $cmd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source }

Set-Alias winget "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"

# ── Claude Code profiles ────────────────────────────────────────
$_localBin = Join-Path $env:USERPROFILE '.local\bin'
if ((Test-Path $_localBin) -and (($env:Path -split ';') -notcontains $_localBin)) {
    $env:Path = "$_localBin;$env:Path"
}

$_claudeExe = Join-Path $_localBin 'claude.exe'
if (-not (Test-Path $_claudeExe)) {
    $_claudeExe = (Get-Command -CommandType Application claude.exe -ErrorAction SilentlyContinue |
                   Select-Object -First 1 -ExpandProperty Source)
}
if ($_claudeExe) {
    function _InvokeClaudeProfile {
        param([string]$ConfigDir)

        $prev = $env:CLAUDE_CONFIG_DIR
        $env:CLAUDE_CONFIG_DIR = $ConfigDir
        try { & $_claudeExe --dangerously-skip-permissions @args } finally { $env:CLAUDE_CONFIG_DIR = $prev }
    }

    function claude-personal { _InvokeClaudeProfile "$env:USERPROFILE\.claude-personal" @args }
    function claude-work { _InvokeClaudeProfile "$env:USERPROFILE\.claude-work" @args }
    function claude { claude-personal @args }
}

# ── VS Code — perfil work (default é ~/.claude-personal via env var do SO)
$_codeExe = (Get-Command -CommandType Application code -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source)
if ($_codeExe) {
    function codew {
        $prev = $env:CLAUDE_CONFIG_DIR
        $env:CLAUDE_CONFIG_DIR = "$env:USERPROFILE\.claude-work"
        try { & $_codeExe @args } finally { $env:CLAUDE_CONFIG_DIR = $prev }
    }
}
