param(
    [switch]$Install,
    [switch]$SkipCompile
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'headset-battery-taskbar-widget.wh.cpp'
$windhawkRoot = 'C:\Program Files\Windhawk'
$compiler = Join-Path $windhawkRoot 'Compiler\bin\clang-20.exe'
$programData = 'C:\ProgramData\Windhawk'
$editorSource = Join-Path $programData 'EditorWorkspace\mod.wh.cpp'
$modsSource = Join-Path $programData 'ModsSource\local@headset-battery-taskbar-widget.wh.cpp'
$flags = Join-Path $programData 'EditorWorkspace\compile_flags.txt'
$fallbackFlags = Join-Path $windhawkRoot 'Compiler\compile_flags.txt'
$output = Join-Path $env:TEMP 'headset-battery-taskbar-widget-test.dll'

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Path -LiteralPath $source)) {
    throw "Source not found: $source"
}

if (-not (Test-Path -LiteralPath $compiler)) {
    throw "Windhawk compiler not found: $compiler"
}

if (-not (Test-Path -LiteralPath $flags)) {
    $flags = $fallbackFlags
}

if (-not (Test-Path -LiteralPath $flags)) {
    throw "Windhawk compile flags not found."
}

if (-not $SkipCompile) {
    Write-Host "Compiling Windhawk mod..."

    $args = @(
        "@$flags",
        '-shared',
        '-o', $output,
        $source,
        '-I', (Join-Path $windhawkRoot 'Compiler\include'),
        '-L', (Join-Path $windhawkRoot 'Compiler\x86_64-w64-mingw32\lib'),
        '-lgdi32',
        '-luser32',
        '-lsetupapi',
        '-lwinmm',
        '-lole32',
        '-lc++',
        '-lc++abi',
        '-lunwind'
    )

    & $compiler @args
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    Write-Host "Compile OK: $output"
}

if ($Install) {
    if (-not (Test-IsAdmin)) {
        Write-Host "Requesting admin permission to sync Windhawk ProgramData files..."
        $elevatedArgs = @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', "`"$PSCommandPath`"",
            '-Install',
            '-SkipCompile'
        )
        $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $elevatedArgs
        exit $process.ExitCode
    }

    Write-Host "Syncing source to Windhawk workspace..."
    Copy-Item -LiteralPath $source -Destination $editorSource -Force
    Copy-Item -LiteralPath $source -Destination $modsSource -Force

    Get-FileHash -LiteralPath $source, $editorSource, $modsSource -Algorithm SHA256 |
        Select-Object Path, Hash |
        Format-Table -AutoSize

    Write-Host "Source synced. Open Windhawk and click Compile Mod to publish it into the active engine."
}
