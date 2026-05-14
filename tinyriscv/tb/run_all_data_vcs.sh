#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_PATH="$(cd "${SCRIPT_DIR}/.." && pwd)"
TB_FILE="${DESIGN_PATH}/tb/tinyriscv_soc_top_with_bridge_downloader_tb.v"
DATA_DIR="${DESIGN_PATH}/Baisc_Inst_Example"
LOG_DIR="${DESIGN_PATH}/tb/log/all_data_vcs"
WAVE_DIR="${DESIGN_PATH}/tb/waves/all_data_vcs"
SUMMARY="${LOG_DIR}/summary.log"
BACKUP="${TB_FILE}.run_all_data_vcs.bak"

mkdir -p "${LOG_DIR}" "${WAVE_DIR}"
cp "${TB_FILE}" "${BACKUP}"

restore_tb() {
    if [[ -f "${BACKUP}" ]]; then
        cp "${BACKUP}" "${TB_FILE}"
        rm -f "${BACKUP}"
    fi
}
trap restore_tb EXIT

: > "${SUMMARY}"

pass_count=0
fail_count=0
total_count=0

for data_file in "${DATA_DIR}"/*.data; do
    data_name="$(basename "${data_file}")"
    data_rel="Baisc_Inst_Example/${data_name}"
    case_name="${data_name%.data}"

    total_count=$((total_count + 1))
    echo "============================================================" | tee -a "${SUMMARY}"
    echo "CASE ${total_count}: ${data_rel}" | tee -a "${SUMMARY}"
    echo "============================================================" | tee -a "${SUMMARY}"

    if command -v perl >/dev/null 2>&1; then
        perl -0pi -e "s#Baisc_Inst_Example/[^\"\\s]+\\.data#${data_rel}#g; s#Loaded [^\":\\n]+\\.data:#Loaded ${data_rel}:#g" "${TB_FILE}"
    else
        sed -i.bak -E "s#Baisc_Inst_Example/[^\"[:space:]]+\\.data#${data_rel}#g; s#Loaded [^\":]+\\.data:#Loaded ${data_rel}:#g" "${TB_FILE}"
        rm -f "${TB_FILE}.bak"
    fi

    if ! FAST_SIM="${FAST_SIM:-1}" bash "${DESIGN_PATH}/tb/vcs_compile.sh"; then
        echo "COMPILE FAIL: ${data_rel}" | tee -a "${SUMMARY}"
        cp "${DESIGN_PATH}/tb/log/vcs_compile_downloader.log" "${LOG_DIR}/${case_name}_compile.log" 2>/dev/null || true
        fail_count=$((fail_count + 1))
        continue
    fi
    cp "${DESIGN_PATH}/tb/log/vcs_compile_downloader.log" "${LOG_DIR}/${case_name}_compile.log" 2>/dev/null || true

    if bash "${DESIGN_PATH}/tb/vcs_sim.sh"; then
        cp "${DESIGN_PATH}/tb/log/vcs_sim_downloader.log" "${LOG_DIR}/${case_name}_sim.log" 2>/dev/null || true
    else
        cp "${DESIGN_PATH}/tb/log/vcs_sim_downloader.log" "${LOG_DIR}/${case_name}_sim.log" 2>/dev/null || true
        echo "SIM FAIL: ${data_rel}" | tee -a "${SUMMARY}"
        fail_count=$((fail_count + 1))
        if [[ -f "${DESIGN_PATH}/tinyriscv_soc_top_with_bridge_downloader_tb.fsdb" ]]; then
            mv "${DESIGN_PATH}/tinyriscv_soc_top_with_bridge_downloader_tb.fsdb" "${WAVE_DIR}/${case_name}.fsdb"
        fi
        continue
    fi

    if grep -q "FINAL PASS: succ=1" "${DESIGN_PATH}/tb/log/vcs_sim_downloader.log"; then
        echo "PASS: ${data_rel}" | tee -a "${SUMMARY}"
        pass_count=$((pass_count + 1))
        if [[ "${SAVE_FSDB:-0}" == "1" && -f "${DESIGN_PATH}/tinyriscv_soc_top_with_bridge_downloader_tb.fsdb" ]]; then
            mv "${DESIGN_PATH}/tinyriscv_soc_top_with_bridge_downloader_tb.fsdb" "${WAVE_DIR}/${case_name}.fsdb"
        else
            rm -f "${DESIGN_PATH}/tinyriscv_soc_top_with_bridge_downloader_tb.fsdb"
        fi
    else
        echo "FAIL: ${data_rel}" | tee -a "${SUMMARY}"
        fail_count=$((fail_count + 1))
        if [[ -f "${DESIGN_PATH}/tinyriscv_soc_top_with_bridge_downloader_tb.fsdb" ]]; then
            mv "${DESIGN_PATH}/tinyriscv_soc_top_with_bridge_downloader_tb.fsdb" "${WAVE_DIR}/${case_name}.fsdb"
        fi
    fi
done

echo "============================================================" | tee -a "${SUMMARY}"
echo "SUMMARY: total=${total_count} pass=${pass_count} fail=${fail_count}" | tee -a "${SUMMARY}"
echo "Logs: ${LOG_DIR}" | tee -a "${SUMMARY}"
echo "Failed-case waves: ${WAVE_DIR}" | tee -a "${SUMMARY}"
echo "============================================================" | tee -a "${SUMMARY}"

if [[ "${fail_count}" -ne 0 ]]; then
    exit 1
fi
