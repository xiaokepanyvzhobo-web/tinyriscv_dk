#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_PATH="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export DESIGN_PATH

BUILD_DIR="${SCRIPT_DIR}/build"
LOG_DIR="${SCRIPT_DIR}/log"
SIMV="${BUILD_DIR}/simv_load_after_lw"

mkdir -p "${BUILD_DIR}" "${LOG_DIR}"
cd "${DESIGN_PATH}"

if [[ ! -x "${SIMV}" ]]; then
    echo "ERROR: ${SIMV} not found or not executable."
    echo "Run: bash liudk_test/load_after_lw_test/vcs_compile.sh"
    exit 1
fi

INST_FILE="${1:-liudk_test/load_after_lw_test/lw_then_addi.data}"

echo "[SIM] DESIGN_PATH=${DESIGN_PATH}"
echo "[SIM] simv=${SIMV}"
echo "[SIM] inst_file=${INST_FILE}"
"${SIMV}" \
    +INST_FILE="${INST_FILE}" \
    -l "${LOG_DIR}/vcs_sim_load_after_lw.log"
