#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_PATH="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export DESIGN_PATH

BUILD_DIR="${SCRIPT_DIR}/build"
LOG_DIR="${SCRIPT_DIR}/log"
SIMV="${BUILD_DIR}/simv_pwm"

mkdir -p "${BUILD_DIR}" "${LOG_DIR}"
cd "${DESIGN_PATH}"

if [[ ! -x "${SIMV}" ]]; then
    echo "ERROR: ${SIMV} not found or not executable."
    echo "Run: bash liudk_test/pwm_test/vcs_compile.sh"
    exit 1
fi

echo "[SIM] DESIGN_PATH=${DESIGN_PATH}"
echo "[SIM] simv=${SIMV}"
"${SIMV}" \
    +INST_FILE=liudk_test/pwm_test/PWM_inst.data \
    +ROM_DUMP=liudk_test/pwm_test/build/downloaded_rom_after_uart.hex \
    -l "${LOG_DIR}/vcs_sim_pwm.log" \
    "$@"
