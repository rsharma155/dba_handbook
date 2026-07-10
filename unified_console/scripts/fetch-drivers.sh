#!/usr/bin/env bash
# Download JDBC drivers into connection_libraries/ (maintainer script).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PG_DIR="$ROOT/connection_libraries/postgres"
MSSQL_DIR="$ROOT/connection_libraries/sqlserver"
PG_JAR="postgresql-42.7.4.jar"
MSSQL_JAR="mssql-jdbc-12.8.1.jre11.jar"

mkdir -p "$PG_DIR" "$MSSQL_DIR"

if [[ ! -f "$PG_DIR/$PG_JAR" ]]; then
  echo "Downloading PostgreSQL JDBC…"
  curl -fsSL "https://jdbc.postgresql.org/download/$PG_JAR" -o "$PG_DIR/$PG_JAR"
fi

if [[ ! -f "$MSSQL_DIR/$MSSQL_JAR" ]]; then
  echo "Downloading Microsoft SQL Server JDBC…"
  curl -fsSL -o "$MSSQL_DIR/$MSSQL_JAR" \
    "https://github.com/microsoft/mssql-jdbc/releases/download/v12.8.1/mssql-jdbc-12.8.1.jre11.jar"
fi

echo "Drivers ready:"
ls -la "$PG_DIR" "$MSSQL_DIR"
