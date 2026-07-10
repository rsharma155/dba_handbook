#!/usr/bin/env bash
#==============================================================================
# generate-dba-handbook.sh
# Generates the PostgreSQL DBA Production Handbook as a self-contained HTML file.
#
# Usage:
#   ./generate-dba-handbook.sh
#   ./generate-dba-handbook.sh /path/to/output.html
#
# Requirements: bash 4+, python3
#==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_OUTPUT="${REPO_ROOT}/output/DBA_Production_Handbook.html"
OUTPUT_PATH="${1:-${DEFAULT_OUTPUT}}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: python3 is required but not found in PATH." >&2
  exit 1
fi

echo "PostgreSQL DBA Handbook Generator"
echo "  Repository: ${REPO_ROOT}"
echo "  Output:     ${OUTPUT_PATH}"

python3 "${SCRIPT_DIR}/build_handbook.py" \
  --root "${REPO_ROOT}" \
  --output "${OUTPUT_PATH}"

echo "Done. Open in a browser:"
echo "  file://${OUTPUT_PATH}"
