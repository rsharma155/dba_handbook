#!/usr/bin/env bash
# Build fat JAR + portable JRE + native launcher executable.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIST="$ROOT/unified_console/dist/DBA-Console-Portable"

"$ROOT/unified_console/scripts/fetch-drivers.sh"

echo "Building connector…"
mvn -q -f "$ROOT/unified_console/connector/pom.xml" package

echo "Building native launcher…"
"$ROOT/unified_console/scripts/build-launcher.sh"

mkdir -p "$DIST/connection_libraries/postgres" "$DIST/connection_libraries/sqlserver"
cp "$ROOT/connection_libraries/postgres/"*.jar "$DIST/connection_libraries/postgres/" 2>/dev/null || true
cp "$ROOT/connection_libraries/sqlserver/"*.jar "$DIST/connection_libraries/sqlserver/" 2>/dev/null || true
cp "$ROOT/unified_console/connector/target/dba-connector-1.0.0.jar" "$DIST/"
cp "$ROOT/unified_console/ui/DBA_Console.html" "$DIST/"

LAUNCHER="$ROOT/unified_console/dist/DBA-Console"
if [[ -f "${LAUNCHER}.exe" ]]; then
  cp "${LAUNCHER}.exe" "$DIST/"
elif [[ -f "$LAUNCHER" ]]; then
  cp "$LAUNCHER" "$DIST/"
  chmod +x "$DIST/DBA-Console"
fi

if command -v jlink >/dev/null 2>&1; then
  echo "Creating portable JRE…"
  jlink --add-modules java.base,java.sql,java.naming,java.desktop,java.management,java.security.jgss,java.instrument,jdk.crypto.ec \
    --strip-debug --no-man-pages --no-header-files --compress=2 \
    --output "$DIST/runtime"
fi

echo ""
echo "Portable bundle: $DIST"
echo "End users double-click: DBA-Console (or DBA-Console.exe on Windows)"
