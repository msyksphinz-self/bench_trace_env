#!/usr/bin/env bash
set -euo pipefail

# run_full_benchmark_fifo.sh
# Run a SPEC CPU2006 benchmark end-to-end via QEMU -> FIFO -> Sniper
# without SimPoint: full detailed simulation, no SIFT files written to disk.
#
# Usage:
#   SPEC_ROOT=... SPECINVOKE=... SNIPER_ROOT=... SIMULATION_DIR=... \
#   QEMU=... QEMU_FLAGS=... QEMU_CPU_OPTIONS=... \
#   QEMU_FRONTEND_PLUGIN=... SNIPER_CONFIG_DIR=... \
#   ./run_full_benchmark_fifo.sh <benchmark> <subcmd>
#
# Arguments:
#   benchmark  - benchmark name, e.g. 429.mcf
#   subcmd     - 1-based subcommand index (line number from specinvoke -n output)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <benchmark> <subcmd>" >&2
  echo "  benchmark : e.g. 429.mcf" >&2
  echo "  subcmd    : 1-based subcommand index" >&2
  exit 1
fi

benchmark="$1"
subcmd="$2"

# ---- required environment variables ----------------------------------------
: "${SPEC_ROOT:?SPEC_ROOT is required}"
: "${SPECINVOKE:?SPECINVOKE is required}"
: "${SNIPER_ROOT:?SNIPER_ROOT is required}"
: "${SIMULATION_DIR:?SIMULATION_DIR is required}"
: "${QEMU:?QEMU is required}"
: "${QEMU_FLAGS:?QEMU_FLAGS is required}"
: "${QEMU_CPU_OPTIONS:?QEMU_CPU_OPTIONS is required}"
: "${QEMU_FRONTEND_PLUGIN:?QEMU_FRONTEND_PLUGIN is required}"
: "${SNIPER_CONFIG_DIR:?SNIPER_CONFIG_DIR is required}"

# Optional Sniper LD path (used in existing flow)
SNIPER_SIM_LD_PATH="${SNIPER_SIM_LD_PATH:-}"
PIN_HOME="${PIN_HOME:-}"

# ---- derived paths ----------------------------------------------------------
run_dir="${SPEC_ROOT}/benchspec/CPU2006/${benchmark}/run/run_base_ref_gcc.0000"

echo "=== Full benchmark run (FIFO): ${benchmark} subcmd=${subcmd} ==="

if [ ! -d "${run_dir}" ]; then
  echo "Error: Run directory not found: ${run_dir}" >&2
  exit 1
fi

# ---- get subcommand ---------------------------------------------------------
subcmds="$(cd "${run_dir}" && "${SPECINVOKE}" -n 2>/dev/null | grep -v "^#" | grep -v "^timer" | grep -v "^$")"
cmd_raw=$(printf '%s\n' "${subcmds}" | awk -v n="${subcmd}" 'NR==n{r=$0} END{print r}')
if [ -z "${cmd_raw}" ]; then
  echo "Error: Subcommand ${subcmd} not found for ${benchmark}" >&2
  exit 1
fi

# ---- determine output directory index (avoid overwriting previous runs) ----
simulation_output_dir="${SIMULATION_DIR}/${benchmark}/full_run"
mkdir -p "${simulation_output_dir}"

run_index=1
while [ -d "${simulation_output_dir}/subcmd_${subcmd}_run${run_index}" ]; do
  run_index=$((run_index + 1))
done
output_subdir="${simulation_output_dir}/subcmd_${subcmd}_run${run_index}"
mkdir -p "${output_subdir}"
output_subdir_abs="$(cd "${output_subdir}" && pwd)"

echo "[${benchmark}] Output directory: ${output_subdir_abs}"

# ---- set up run directory ---------------------------------------------------
# specinvoke commands use relative path "../run_base_ref_gcc.0000/binary"
# so we must create that sibling directory alongside run_dir, matching the
# structure used in run_sift_single_simpoint.sh.
run_base_dir="${output_subdir_abs}/run_base_ref_gcc.0000"
if [ ! -d "${run_base_dir}" ]; then
  cp -r "${run_dir}" "${run_base_dir}" 2>/dev/null || true
fi

run_work_dir="${output_subdir_abs}/run_dir"
mkdir -p "${run_work_dir}"
if [ -d "${run_dir}" ] && [ "$(ls -A "${run_dir}" 2>/dev/null)" ]; then
  cp -r "${run_dir}"/* "${run_work_dir}/" 2>&1 || {
    echo "Warning: Failed to copy some files from ${run_dir} to ${run_work_dir}" >&2
  }
fi

# ---- parse command (same logic as run_sift_single_simpoint.sh) -------------
cmd_clean=$(printf "%s\n" "$cmd_raw" | awk '{
  gsub(/ [0-9]*>>* *[^ ]*/, "")
  print
}')

stdin_redirect=
cmd_no_stdin=$(echo "$cmd_clean" | awk '{
  if (match($0, / [<] [^ ]+/)) {
    print substr($0, 1, RSTART-1) substr($0, RSTART+RLENGTH)
  } else {
    print
  }
}')
if echo "$cmd_clean" | grep -qE ' [<] [^ ]+'; then
  stdin_redirect=$(echo "$cmd_clean" | awk 'match($0, / [<] [^ ]+/) { print substr($0, RSTART+3, RLENGTH-3); exit }')
  cmd_clean="$cmd_no_stdin"
fi
cmd_suffix=$(echo "$cmd_clean" | awk '{$1=""; sub(/^[ \t]+/, ""); print}')
cmd_suffix_noL=$(echo "$cmd_suffix" | awk '{gsub(/^-L [^ ]* /, ""); gsub(/^[ \t]+/, ""); print}')

first_word=$(printf '%s\n' "$cmd_clean" | awk '{print $1; exit}')
if [ "$first_word" = "$QEMU" ]; then
  cmd_for_qemu="$cmd_suffix_noL"
else
  cmd_for_qemu=$(echo "$cmd_clean" | awk '{gsub(/ -L [^ ]+/, ""); print}')
fi

# ---- create FIFO ------------------------------------------------------------
fifo_tmpdir="$(mktemp -d /tmp/sniper_fifo_XXXXXX)"
FIFO_PREFIX="${fifo_tmpdir}/trace"
FIFO_SIFT="${FIFO_PREFIX}.app0.th0.sift"

# Cleanup on exit (success or failure)
cleanup() {
  echo "[${benchmark}] Cleaning up FIFOs in ${fifo_tmpdir}..."
  # Kill background Sniper if still running
  if [ -n "${SNIPER_PID:-}" ] && kill -0 "${SNIPER_PID}" 2>/dev/null; then
    echo "[${benchmark}] Killing Sniper (PID ${SNIPER_PID})..."
    kill "${SNIPER_PID}" 2>/dev/null || true
    wait "${SNIPER_PID}" 2>/dev/null || true
  fi
  rm -rf "${fifo_tmpdir}"
}
trap cleanup EXIT

# Create the FIFO file that Sniper will read
mkfifo "${FIFO_SIFT}"
echo "[${benchmark}] Created FIFO: ${FIFO_SIFT}"

# ---- LD path setup ----------------------------------------------------------
original_ld_path="${LD_LIBRARY_PATH:-}"
sniper_vm_ld_path="${SNIPER_SIM_LD_PATH:-${original_ld_path}}"
sniper_script_ld_path="${original_ld_path}"

# ---- start Sniper in background ---------------------------------------------
RUN_SNIPER="${SNIPER_ROOT}/run-sniper"
CONFIG_BASE="${SNIPER_CONFIG_DIR}/riscv.cfg"
SPEC_OVERRIDE_CFG="${SCRIPT_DIR}/../sniper_configs/spec.cfg"
LOG_FILE="${output_subdir_abs}/sniper.log"

echo "[${benchmark}] Starting Sniper (background)..."

# --traces expects the base path without .sift suffix; findtrace() appends .sift
"${RUN_SNIPER}" \
  -v \
  -c "${CONFIG_BASE}" \
  -c "${SPEC_OVERRIDE_CFG}" \
  -c "general/magic=false" \
  -c "general/app=${benchmark}" \
  -c "perf_model/core/rob_timer/vec_physical_registers=40" \
  -c "perf_model/core/rob_timer/vec_reserve_policy=alloc_none" \
  -c "perf_model/dram/latency=200" \
  -c "perf_model/l1_dcache/outstanding_misses=48" \
  -c "perf_model/l2_cache/outstanding_misses=9" \
  --traces="${FIFO_PREFIX}.app0.th0" \
  -d "${output_subdir_abs}" \
  > "${LOG_FILE}" 2>&1 &
SNIPER_PID=$!
echo "[${benchmark}] Sniper PID: ${SNIPER_PID}"

# ---- start QEMU (foreground) ------------------------------------------------
# fast_forward_target=0, detailed_target=0 → full detailed simulation
echo "[${benchmark}] Starting QEMU..."

QEMU_LOG="${output_subdir_abs}/qemu.log"

QEMU_EXIT=0
if [ -n "$stdin_redirect" ]; then
  if [ ! -r "${run_work_dir}/${stdin_redirect}" ]; then
    echo "Error: stdin file not found: ${run_work_dir}/${stdin_redirect}" >&2
    exit 1
  fi
  ( cd "${run_work_dir}" && \
    SNIPER_ROOT="${SNIPER_ROOT}" GRAPHITE_ROOT="${SNIPER_ROOT}" \
    PIN_HOME="${PIN_HOME}" \
    PIN_LD_RESTORE_REQUIRED=1 \
    PIN_VM_LD_LIBRARY_PATH="${sniper_vm_ld_path}" \
    PIN_APP_LD_LIBRARY_PATH="${original_ld_path}" \
    SNIPER_SCRIPT_LD_LIBRARY_PATH="${sniper_script_ld_path}" \
    LD_LIBRARY_PATH="${sniper_vm_ld_path}" \
    LD_PRELOAD= \
    QEMU_CPU="${QEMU_CPU_OPTIONS}" \
    "${QEMU}" ${QEMU_FLAGS} \
      -plugin "${QEMU_FRONTEND_PLUGIN}",verbose=on,response_files=off,fast_forward_target=0,detailed_target=9999999999999999,output_file="${FIFO_PREFIX}.app0.th0" \
      ${cmd_for_qemu} \
    0< "${stdin_redirect}" \
  ) > "${QEMU_LOG}" 2>&1 || QEMU_EXIT=$?
else
  ( cd "${run_work_dir}" && \
    SNIPER_ROOT="${SNIPER_ROOT}" GRAPHITE_ROOT="${SNIPER_ROOT}" \
    PIN_HOME="${PIN_HOME}" \
    PIN_LD_RESTORE_REQUIRED=1 \
    PIN_VM_LD_LIBRARY_PATH="${sniper_vm_ld_path}" \
    PIN_APP_LD_LIBRARY_PATH="${original_ld_path}" \
    SNIPER_SCRIPT_LD_LIBRARY_PATH="${sniper_script_ld_path}" \
    LD_LIBRARY_PATH="${sniper_vm_ld_path}" \
    LD_PRELOAD= \
    QEMU_CPU="${QEMU_CPU_OPTIONS}" \
    "${QEMU}" ${QEMU_FLAGS} \
      -plugin "${QEMU_FRONTEND_PLUGIN}",verbose=on,response_files=off,fast_forward_target=0,detailed_target=9999999999999999,output_file="${FIFO_PREFIX}.app0.th0" \
      ${cmd_for_qemu} \
  ) > "${QEMU_LOG}" 2>&1 || QEMU_EXIT=$?
fi

if [ "${QEMU_EXIT}" -ne 0 ]; then
  echo "Error: QEMU exited with status ${QEMU_EXIT}. Check log: ${QEMU_LOG}" >&2
  tail -20 "${QEMU_LOG}" >&2
  exit 1
fi
echo "[${benchmark}] QEMU completed"

# ---- wait for Sniper to finish ----------------------------------------------
echo "[${benchmark}] Waiting for Sniper (PID ${SNIPER_PID})..."
wait "${SNIPER_PID}"
SNIPER_EXIT=$?
SNIPER_PID=""  # Mark as already reaped so cleanup doesn't try again

if [ "${SNIPER_EXIT}" -ne 0 ]; then
  echo "Error: Sniper exited with status ${SNIPER_EXIT}. Check log: ${LOG_FILE}" >&2
  exit 1
fi

# ---- verify results ---------------------------------------------------------
if [ ! -f "${output_subdir_abs}/sim.out" ]; then
  echo "Error: Sniper simulation failed (sim.out not found). Check log: ${LOG_FILE}" >&2
  exit 1
fi

echo "[${benchmark}] Simulation completed. Results in: ${output_subdir_abs}"

# ---- convert SQLite to JSON if present --------------------------------------
# Note: convert_sniper_sqlite.py writes the output file itself; do NOT redirect
# stdout to the same file, as it would overwrite the JSON with the progress log.
if [ -f "${output_subdir_abs}/sim.stats.sqlite3" ]; then
  SQLITE_OUTPUT_FORMAT="${SQLITE_OUTPUT_FORMAT:-json}"
  "${SCRIPT_DIR}/convert_sniper_sqlite.py" \
    "${output_subdir_abs}/sim.stats.sqlite3" \
    --format "${SQLITE_OUTPUT_FORMAT}" \
    --output "${output_subdir_abs}/sim.stats.${SQLITE_OUTPUT_FORMAT}" 2>&1 || {
    echo "Warning: Failed to convert SQLite to ${SQLITE_OUTPUT_FORMAT}" >&2
  }
fi

echo "[${benchmark}] Full run completed successfully (subcmd=${subcmd}, run=${run_index})"
