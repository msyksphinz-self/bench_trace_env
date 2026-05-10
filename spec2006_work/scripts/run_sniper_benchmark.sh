#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -lt 2 ]; then
  echo "Usage: SNIPER_ROOT=... SIFT_DIR=... SIMULATION_DIR=... CONFIG_DIR=... SIMPOINT_INTERVAL=... $0 <benchmark> <sift_file> [config_options...]" >&2
  exit 1
fi

benchmark="$1"
sift_file="$2"
shift 2
extra_config_options="$@"

: "${SNIPER_ROOT:?SNIPER_ROOT is required}"
: "${SIFT_DIR:?SIFT_DIR is required}"
: "${SIMULATION_DIR:?SIMULATION_DIR is required}"
: "${CONFIG_DIR:?CONFIG_DIR is required}"
: "${SIMPOINT_INTERVAL:?SIMPOINT_INTERVAL is required}"

sift_output_dir="${SIFT_DIR}/${benchmark}"
simulation_output_dir="${SIMULATION_DIR}/${benchmark}"

echo "=== Running Sniper simulation for ${benchmark} ==="

# Check if SIFT file exists
if [ ! -f "${sift_file}" ]; then
  echo "Error: SIFT file ${sift_file} not found." >&2
  exit 1
fi

# Create simulation output directory
mkdir -p "${simulation_output_dir}"

# Get base name for output directory (without .sift extension)
sift_basename=$(basename "${sift_file}" .sift)
output_subdir="${simulation_output_dir}/${sift_basename}"
mkdir -p "${output_subdir}"

# Build run-sniper command
# Use similar configuration as prave_date2026/simulations
RUN_SNIPER="${SNIPER_ROOT}/run-sniper"
# CONFIG_BASE="-c ${CONFIG_DIR}/riscv-base.cfg"
CONFIG_BASE="-c ${CONFIG_DIR}/riscv.cfg"
SPEC_OVERRIDE_CFG="-c ${SCRIPT_DIR}/../sniper_configs/spec.cfg"
# CONFIG_MEDIUMBOOM="-c ${CONFIG_DIR}/riscv-mediumboom.v1024_d256.cfg"
# CONFIG_BASE_HIGH="-c ${CONFIG_DIR}/riscv-base-high.cfg"
CONFIG_MEDIUMBOOM=
CONFIG_BASE_HIGH=

# Calculate roi-icount parameters based on SIMPOINT_INTERVAL
# fast-forward: 20% of INTERVAL, detailed simulation: 80% of INTERVAL
WARMUP_LENGTH=$((SIMPOINT_INTERVAL * 20 / 100))
DETAILED_LENGTH=$((SIMPOINT_INTERVAL * 80 / 100))
ROI_ICOUNT_PARAMS="0:${WARMUP_LENGTH}:${DETAILED_LENGTH}"

# Default configuration options (can be overridden by extra_config_options)
DEFAULT_OPTIONS=(
  "-v"
  "${CONFIG_BASE}"
  "${SPEC_OVERRIDE_CFG}"
  "${CONFIG_MEDIUMBOOM}"
  "${CONFIG_BASE_HIGH}"
  "--roi-script"
  "-s" "roi-icount:${ROI_ICOUNT_PARAMS}"
  "-c" "general/magic=false"
  "-c" "general/app=${benchmark}"
  "-c" "perf_model/core/rob_timer/vec_physical_registers=40"
  "-c" "perf_model/core/rob_timer/vec_reserve_policy=alloc_none"
  "-c" "perf_model/dram/latency=200"
  "-c" "perf_model/l1_dcache/outstanding_misses=48"
  "-c" "perf_model/l2_cache/outstanding_misses=9"
  "--traces=${sift_file}"
)

# Change to output directory and run simulation
cd "${output_subdir}"

log_file="${output_subdir}/sniper_run.log"

# Check if running in quiet mode (parallel execution)
if [ "${QUIET_MODE:-0}" = "1" ]; then
  # Quiet mode: only show progress, save detailed output to log file
    echo "[${benchmark}] Running Sniper simulation with SIFT file: ${sift_file}"
    echo "${RUN_SNIPER}" -d "${output_subdir}" "${DEFAULT_OPTIONS[@]}" ${extra_config_options}
#  "${RUN_SNIPER}" -d "${output_subdir}" "${DEFAULT_OPTIONS[@]}" ${extra_config_options} > "${log_file}" 2>&1
  if [ $? -eq 0 ]; then
    echo "[${benchmark}] Simulation completed: ${output_subdir}"
  else
    echo "[${benchmark}] Simulation failed: ${output_subdir} (check ${log_file})" >&2
    exit 1
  fi
else
  # Verbose mode: show all output (single execution)
  echo "[${benchmark}] Running Sniper simulation with SIFT file: ${sift_file}"
  echo "[${benchmark}] Output directory: ${output_subdir}"
  echo "[${benchmark}] Saving execution log to: ${log_file}"

  "${RUN_SNIPER}" -d "${output_subdir}" "${DEFAULT_OPTIONS[@]}" ${extra_config_options} 2>&1 | tee "${log_file}"

  echo "[${benchmark}] Simulation completed: ${output_subdir}"
  echo "=== Completed Sniper simulation for ${benchmark} ==="
fi
