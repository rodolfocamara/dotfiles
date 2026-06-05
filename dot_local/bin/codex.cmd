@echo off
REM ---------------------------------------------------------------------------
REM Stable wrapper for the `codex` CLI (OpenAI) on Windows.
REM
REM nvm-windows exposes globals only for the *active* node version, so a plain
REM `codex` on PATH breaks the moment you `nvm use` another version. Apps that
REM store an absolute binary path (e.g. T3 Code's Codex app-server provider)
REM then fail with "Codex App Server process exited with code 1".
REM
REM This pins codex to one node version and always invokes it from there.
REM Windows counterpart of ~/.local/bin/codex (the bash wrapper) on the WSL side.
REM
REM First-time setup (pick a version you don't change often):
REM     nvm install 24.15.0
REM     nvm use 24.15.0
REM     npm install -g @openai/codex
REM
REM Override the pinned version ad hoc:
REM     set CODEX_NODE_VERSION=v22.14.0 ^&^& codex ...
REM ---------------------------------------------------------------------------
setlocal

if not defined CODEX_NODE_VERSION set "CODEX_NODE_VERSION=v24.15.0"

set "CODEX_BIN=%LOCALAPPDATA%\nvm\%CODEX_NODE_VERSION%\codex.cmd"

if exist "%CODEX_BIN%" (
  call "%CODEX_BIN%" %*
  exit /b %ERRORLEVEL%
)

>&2 echo codex: not installed for node version %CODEX_NODE_VERSION%
>&2 echo Fix with:
>&2 echo   nvm use %CODEX_NODE_VERSION:v=%
>&2 echo   npm install -g @openai/codex
>&2 echo.
>&2 echo Or temporarily use another version:
>&2 echo   set CODEX_NODE_VERSION=v22.14.0 ^&^& codex ...
exit /b 127
