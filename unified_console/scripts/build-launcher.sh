#!/usr/bin/env bash
# Build native DBA-Console launcher for the current OS/architecture.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
NAME="DBA-Console"
SRC="$ROOT/launcher"

mkdir -p "$OUT"
cd "$SRC"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  arm64|aarch64) ARCH=arm64 ;;
esac
case "$OS" in
  darwin) GOOS=darwin ;;
  linux) GOOS=linux ;;
  mingw*|msys*|cygwin*|windows_nt) GOOS=windows ;;
  *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

EXT=""
if [[ "$GOOS" == "windows" ]]; then
  EXT=".exe"
fi

OUT_FILE="$OUT/${NAME}${EXT}"

echo "Building $OUT_FILE ($GOOS/$ARCH)…"
GOOS="$GOOS" GOARCH="$ARCH" go build -ldflags="-s -w" -o "$OUT_FILE" .

echo "Done: $OUT_FILE"
