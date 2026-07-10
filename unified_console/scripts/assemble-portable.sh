#!/usr/bin/env bash
# Assemble ultra-light portable bundles: native Go binary + HTML only (no Java/JAR/runtime).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
WIN_DIR="$DIST/DBA-Console-Portable-Windows"
MAC_DIR="$DIST/DBA-Console-Portable-Mac"
UI="$ROOT/ui/DBA_Console.html"

echo "Embedding SQL scripts into console HTML…"
python3 "$ROOT/shell/build_console.py"

[[ -f "$UI" ]] || { echo "Missing $UI" >&2; exit 1; }

"$ROOT/scripts/build.sh"

stage() {
  local dir="$1"
  local exe_name="$2"
  local bin="$3"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp "$bin" "$dir/$exe_name"
  cp "$UI" "$dir/DBA_Console.html"
}

stage "$WIN_DIR" "DBA-Console.exe" "$DIST/DBA-Console.exe"

stage "$MAC_DIR" "DBA-Console" "$DIST/DBA-Console-mac"
chmod +x "$MAC_DIR/DBA-Console"

# Optional Authenticode signing when building on Windows with a certificate configured.
if [[ "$(uname -s)" =~ ^(MINGW|MSYS|CYGWIN) ]] && command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ROOT/scripts/sign-windows.ps1" -ExePath "$WIN_DIR/DBA-Console.exe" || true
fi

cd "$DIST"
rm -f DBA-Console-Portable-Windows.zip DBA-Console-Portable-Mac.zip
zip -rq DBA-Console-Portable-Windows.zip DBA-Console-Portable-Windows
zip -rq DBA-Console-Portable-Mac.zip DBA-Console-Portable-Mac

echo ""
echo "Ready (native Go — no Java):"
du -sh "$WIN_DIR" "$MAC_DIR"
echo "  Windows zip: $DIST/DBA-Console-Portable-Windows.zip"
echo "  macOS zip:   $DIST/DBA-Console-Portable-Mac.zip"
