#!/usr/bin/env bash
# Cross-compile DBA-Console launcher for Windows, macOS, and Linux.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
SRC="$ROOT/launcher"

mkdir -p "$OUT"
cd "$SRC"

build() {
  local goos="$1" goarch="$2" ext=""
  [[ "$goos" == "windows" ]] && ext=".exe"
  local out="$OUT/DBA-Console-${goos}-${goarch}${ext}"
  echo "Building $out…"
  GOOS="$goos" GOARCH="$goarch" go build -ldflags="-s -w" -o "$out" .
}

build windows amd64
build darwin arm64
build darwin amd64
build linux amd64

echo "Launchers written to $OUT/"
