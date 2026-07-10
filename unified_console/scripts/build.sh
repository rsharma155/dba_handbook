#!/usr/bin/env bash
# Build native DBA-Console binaries (Go — no Java/JAR required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$ROOT/cmd/dba-console"
DIST="$ROOT/dist"
LDFLAGS="-s -w"

cd "$CMD"
go mod tidy

mkdir -p "$DIST"

echo "Building Windows amd64…"
CGO_ENABLED=0 GOOS=windows GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "$DIST/DBA-Console.exe" .

echo "Building macOS arm64…"
CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -ldflags="$LDFLAGS" -o "$DIST/DBA-Console-mac-arm64" .

echo "Building macOS amd64…"
CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -ldflags="$LDFLAGS" -o "$DIST/DBA-Console-mac-amd64" .

lipo -create -output "$DIST/DBA-Console-mac" "$DIST/DBA-Console-mac-arm64" "$DIST/DBA-Console-mac-amd64"
chmod +x "$DIST/DBA-Console-mac" "$DIST/DBA-Console-mac-arm64" "$DIST/DBA-Console-mac-amd64"

ls -lh "$DIST/DBA-Console.exe" "$DIST/DBA-Console-mac"
echo "Done."
