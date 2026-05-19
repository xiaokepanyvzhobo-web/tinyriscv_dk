#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_PATH="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export DESIGN_PATH

FILELIST="${SCRIPT_DIR}/sID_tb.f"
BUILD_DIR="${SCRIPT_DIR}/build"
LOG_DIR="${SCRIPT_DIR}/log"
SIMV="${BUILD_DIR}/simv_sID"

mkdir -p "${BUILD_DIR}" "${LOG_DIR}"
cd "${DESIGN_PATH}"

VCS_OPTS=(
    -full64
    -sverilog
    +v2k
    -timescale=1ns/1ps
    -debug_access+all
    -kdb
    +define+FSDB
    +vcs+fsdbon
    "+incdir+${DESIGN_PATH}/rtl/core"
    "+incdir+${DESIGN_PATH}/rtl/perips"
    "+incdir+${DESIGN_PATH}/rtl/utils"
    "+incdir+${DESIGN_PATH}/rtl/debug"
    "+incdir+${DESIGN_PATH}/rtl/soc"
    -f "${FILELIST}"
    -top sID_tb
    -Mdir="${BUILD_DIR}/csrc"
    -o "${SIMV}"
    -l "${LOG_DIR}/vcs_compile_sID.log"
)

if [[ "${FAST_SIM:-1}" != "0" ]]; then
    VCS_OPTS+=(+define+FAST_UART_SIM)
fi

if [[ "${DUMP:-1}" == "0" ]]; then
    VCS_OPTS+=(+define+NO_DUMP)
fi

if [[ -n "${VERDI_HOME:-}" && -d "${VERDI_HOME}/share/PLI/VCS/LINUX64" ]]; then
    VCS_OPTS+=(
        -P "${VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab"
           "${VERDI_HOME}/share/PLI/VCS/LINUX64/pli.a"
    )
elif [[ -n "${NOVAS_HOME:-}" && -d "${NOVAS_HOME}/share/PLI/VCS/LINUX64" ]]; then
    VCS_OPTS+=(
        -P "${NOVAS_HOME}/share/PLI/VCS/LINUX64/novas.tab"
           "${NOVAS_HOME}/share/PLI/VCS/LINUX64/pli.a"
    )
fi

echo "[VCS] DESIGN_PATH=${DESIGN_PATH}"
echo "[VCS] filelist=${FILELIST}"
echo "[VCS] output=${SIMV}"
echo "[VCS] FAST_SIM=${FAST_SIM:-1}"
echo "[VCS] DUMP=${DUMP:-1}"
vcs "${VCS_OPTS[@]}"
