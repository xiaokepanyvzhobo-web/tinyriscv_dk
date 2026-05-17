#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

BUILD_DIR="${SCRIPT_DIR}/build/vcs"
LOG_DIR="${SCRIPT_DIR}/log"
WAVE_DIR="${SCRIPT_DIR}/waves"
SIMV="${BUILD_DIR}/simv_iic_dk_tb"
FILELIST="${SCRIPT_DIR}/filelist_vcs.f"

mkdir -p "${BUILD_DIR}" "${LOG_DIR}" "${WAVE_DIR}"

VCS_OPTS=(
    -full64
    -sverilog
    +v2k
    -timescale=1ns/1ps
    -debug_access+all
    -kdb
    +define+FSDB
    +vcs+fsdbon
    -f "${FILELIST}"
    -top iic_dk_tb
    -Mdir="${BUILD_DIR}/csrc"
    -o "${SIMV}"
    -l "${LOG_DIR}/vcs_compile_iic_dk_tb.log"
)

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
else
    echo "[VCS] WARNING: VERDI_HOME/NOVAS_HOME PLI path not found."
    echo "[VCS]          If FSDB system tasks fail, export VERDI_HOME or NOVAS_HOME first."
fi

echo "[VCS] compile iic_dk_tb"
echo "[VCS] filelist=${FILELIST}"
echo "[VCS] simv=${SIMV}"
vcs "${VCS_OPTS[@]}"

echo "[VCS] run simulation"
"${SIMV}" -l "${LOG_DIR}/vcs_sim_iic_dk_tb.log" "$@"

if [[ -f "${WAVE_DIR}/iic_dk_tb.fsdb" ]]; then
    echo "[VCS] FSDB generated: ${WAVE_DIR}/iic_dk_tb.fsdb"
else
    echo "[VCS] WARNING: FSDB was not generated. Check ${LOG_DIR}/vcs_sim_iic_dk_tb.log"
fi
