#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

FILELIST="${SCRIPT_DIR}/filelist_vcs.f"
FSDB="${1:-${SCRIPT_DIR}/waves/iic_dk_tb.fsdb}"
LOG_DIR="${SCRIPT_DIR}/log/verdi"

mkdir -p "${LOG_DIR}"

if [[ ! -f "${FSDB}" ]]; then
    echo "ERROR: FSDB not found: ${FSDB}"
    echo "Run first: bash run_vcs.sh"
    exit 1
fi

echo "[VERDI] filelist=${FILELIST}"
echo "[VERDI] fsdb=${FSDB}"

verdi -full64 \
      -sverilog \
      -f "${FILELIST}" \
      -top iic_dk_tb \
      -ssf "${FSDB}" \
      -logdir "${LOG_DIR}" \
      "$@"
