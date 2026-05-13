#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"
export DESIGN_PATH

BUILD_DIR="${DESIGN_PATH}/tb/vcs_build"
LOG_DIR="${DESIGN_PATH}/tb/log"
SIMV="${BUILD_DIR}/simv_downloader"

mkdir -p "${LOG_DIR}"
cd "${DESIGN_PATH}"

if [[ ! -x "${SIMV}" ]]; then
    echo "ERROR: ${SIMV} not found or not executable."
    echo "Run: bash tb/vcs_compile.sh"
    exit 1
fi

echo "[SIM] DESIGN_PATH=${DESIGN_PATH}"
echo "[SIM] simv=${SIMV}"
"${SIMV}" -l "${LOG_DIR}/vcs_sim_downloader.log" "$@"

