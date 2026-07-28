#!/usr/bin/env bash
# Install the pinned official Wave release after verifying GitHub's digest.

set -euo pipefail

version="0.14.5"
asset="waveterm-linux-x64-${version}.pacman"
sha256="f4a0ebe926697106d47aa685e7e8f1d368969f79a00a0fad337b83b1aed23378"

[[ "$(uname -s)" == "Linux" ]] || { echo "Wave installer: Linux only"; exit 0; }
[[ "$(uname -m)" == "x86_64" ]] || { echo "Wave installer: x86_64 only"; exit 1; }
command -v pacman >/dev/null 2>&1 || { echo "Wave installer: pacman is required"; exit 1; }

tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

url="https://github.com/wavetermdev/waveterm/releases/download/v${version}/${asset}"
curl --fail --location --proto '=https' --tlsv1.2 --output "$tmp_dir/$asset" "$url"
printf '%s  %s\n' "$sha256" "$tmp_dir/$asset" | sha256sum --check
sudo pacman -U --needed --noconfirm "$tmp_dir/$asset"
