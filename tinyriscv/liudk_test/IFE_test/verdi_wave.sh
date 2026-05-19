#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_PATH="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export DESIGN_PATH

FILELIST="${SCRIPT_DIR}/IFE_tb.f"
FSDB="${SCRIPT_DIR}/build/IFE_tb.fsdb"
LOG_DIR="${SCRIPT_DIR}/log"

mkdir -p "${LOG_DIR}"
cd "${DESIGN_PATH}"

if [[ ! -f "${FSDB}" ]]; then
    echo "ERROR: ${FSDB} not found."
    echo "Run: bash liudk_test/IFE_test/vcs_sim.sh"
    exit 1
fi

echo "[VERDI] DESIGN_PATH=${DESIGN_PATH}"
echo "[VERDI] filelist=${FILELIST}"
echo "[VERDI] fsdb=${FSDB}"
verdi -full64 \
      -sverilog \
      "+incdir+${DESIGN_PATH}/rtl/core" \
      "+incdir+${DESIGN_PATH}/rtl/perips" \
      "+incdir+${DESIGN_PATH}/rtl/utils" \
      "+incdir+${DESIGN_PATH}/rtl/debug" \
      "+incdir+${DESIGN_PATH}/rtl/soc" \
      -f "${FILELIST}" \
      -ssf "${FSDB}" \
      -logdir "${LOG_DIR}" \
      "$@"
