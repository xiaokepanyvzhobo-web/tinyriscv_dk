#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"
export DESIGN_PATH

FILELIST="${DESIGN_PATH}/tb/tinyriscv_soc_top_with_bridge_downloader_tb.f"
FSDB="${DESIGN_PATH}/tinyriscv_soc_top_with_bridge_downloader_tb.fsdb"
LOG_DIR="${DESIGN_PATH}/tb/log"

mkdir -p "${LOG_DIR}"
cd "${DESIGN_PATH}"

if [[ ! -f "${FSDB}" ]]; then
    echo "ERROR: ${FSDB} not found."
    echo "Run: bash tb/vcs_sim.sh"
    exit 1
fi

echo "[VERDI] DESIGN_PATH=${DESIGN_PATH}"
echo "[VERDI] filelist=${FILELIST}"
echo "[VERDI] fsdb=${FSDB}"
verdi -full64 \
      -sverilog \
      "+incdir+${DESIGN_PATH}/rtl/core" \
      -f "${FILELIST}" \
      -ssf "${FSDB}" \
      -logdir "${LOG_DIR}" \
      "$@"

