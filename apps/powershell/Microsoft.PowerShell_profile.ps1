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
$_isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ── Starship prompt + title wrapper (cached init) ───────────────
_CacheInitScript -Name 'starship' -Exe 'starship' -Generator { & starship init powershell }
$_starshipPrompt = $function:prompt

function prompt {
    $prefix = if ($_isAdmin) { "🛡️ " } else { "" }
    $host.UI.RawUI.WindowTitle = "$prefix$($PWD.Path.Replace($HOME, '~'))"
    & $_starshipPrompt
}

# ── k9s completion (cached) ─────────────────────────────────────
_CacheInitScript -Name 'k9s' -Exe 'k9s' -Generator { k9s completion powershell }

# ── Zoxide (cached init) ────────────────────────────────────────
_CacheInitScript -Name 'zoxide' -Exe 'zoxide' -Generator { zoxide init powershell }

# ── Useful shortcuts ────────────────────────────────────────────
function mkcd { param([string]$dir) New-Item -ItemType Directory -Path $dir -Force | Out-Null; Set-Location $dir }
function which { param([string]$cmd) Get-Command $cmd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source }

Set-Alias winget "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
