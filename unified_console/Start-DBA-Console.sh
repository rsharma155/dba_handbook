#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PORT="${PORT:-8742}"

if [[ -f "$HERE/dba-connector-1.0.0.jar" ]]; then
  ROOT="$HERE"
  JAR="$HERE/dba-connector-1.0.0.jar"
else
  ROOT="$(cd "$HERE/.." && pwd)"
  JAR="$ROOT/unified_console/connector/target/dba-connector-1.0.0.jar"
fi

if [[ -x "$HERE/runtime/bin/java" ]]; then
  JAVA="$HERE/runtime/bin/java"
elif [[ -x "$ROOT/unified_console/dist/DBA-Console-Portable/runtime/bin/java" ]]; then
  JAVA="$ROOT/unified_console/dist/DBA-Console-Portable/runtime/bin/java"
elif command -v java >/dev/null 2>&1; then
  JAVA="java"
else
  echo "Java not found. Run ./unified_console/scripts/build-portable.sh" >&2
  exit 1
fi

[[ -f "$JAR" ]] || { echo "Connector JAR missing: $JAR" >&2; exit 1; }

cd "$ROOT"
"$JAVA" -jar "$JAR" --port "$PORT" &
PID=$!
sleep 1

if command -v open >/dev/null 2>&1; then open "http://127.0.0.1:${PORT}/"
elif command -v xdg-open >/dev/null 2>&1; then xdg-open "http://127.0.0.1:${PORT}/"
fi

echo "DBA Console: http://127.0.0.1:${PORT}/ (PID $PID)"
wait "$PID"
