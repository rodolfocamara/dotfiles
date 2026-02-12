# Starship prompt
Invoke-Expression (&starship init powershell)

# Aliases estilo Bash
Set-Alias grep 'Select-String'

if (Test-Path Alias:ls) { Remove-Item Alias:ls -ErrorAction SilentlyContinue }
function ls  { eza --git --icons --group-directories-first @args }
function ll  { eza -lh --git --icons --group-directories-first @args }
function la  { eza -lha --git --icons --group-directories-first @args }

function Set-TerminalTitle {
    $path = $PWD.Path.Replace($HOME, '~')
    $adminPrefix = if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        "🛡️ "
    } else {
        ""
    }

    $host.UI.RawUI.WindowTitle = "$adminPrefix$path"
}
Register-EngineEvent PowerShell.OnIdle -Action { Set-TerminalTitle } | Out-Null