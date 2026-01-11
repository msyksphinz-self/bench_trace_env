#!/usr/bin/env bash
set -euo pipefail

# Get script directory at the start (before any cd commands)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -ne 4 ]; then
  echo "Usage: SPEC_ROOT=... SPECINVOKE=... SIMPOINT_DIR=... SIFT_DIR=... SNIPER_ROOT=... PIN_HOME=... SNIPER_SIM_LD_PATH=... QEMU=... QEMU_FLAGS=... QEMU_CPU_OPTIONS=... SNIPER_CONFIG_DIR=... SIMULATION_DIR=... $0 <benchmark> <subcmd> <simpoint> <simpoint_interval>" >&2
  exit 1
fi

benchmark="$1"
subcmd="$2"
simpoint="$3"
SIMPOINT_INTERVAL="$4"

: "${SPEC_ROOT:?SPEC_ROOT is required}"
: "${SPECINVOKE:?SPECINVOKE is required}"
: "${SIMPOINT_DIR:?SIMPOINT_DIR is required}"
: "${SIFT_DIR:?SIFT_DIR is required}"
: "${SNIPER_ROOT:?SNIPER_ROOT is required}"
: "${PIN_HOME:?PIN_HOME is required}"
: "${SNIPER_SIM_LD_PATH:?SNIPER_SIM_LD_PATH is required}"
: "${QEMU:?QEMU is required}"
: "${QEMU_FLAGS:?QEMU_FLAGS is required}"
: "${QEMU_CPU_OPTIONS:?QEMU_CPU_OPTIONS is required}"
: "${SNIPER_CONFIG_DIR:?SNIPER_CONFIG_DIR is required}"
: "${SIMULATION_DIR:?SIMULATION_DIR is required}"
: "${SIMPOINT_INTERVAL:?SIMPOINT_INTERVAL is required}"

run_dir="${SPEC_ROOT}/benchspec/CPU2006/${benchmark}/run/run_base_ref_gcc.0000"
simpoint_output_dir="${SIMPOINT_DIR}/${benchmark}"
sift_output_dir="${SIFT_DIR}/${benchmark}"

echo "=== Generating SIFT and running Sniper for ${benchmark} subcmd=${subcmd} simpoint=${simpoint} ==="

if [ ! -d "${simpoint_output_dir}" ]; then
  echo "Error: SimPoint directory ${simpoint_output_dir} not found. Please run 'make run_simpoint_${benchmark}' first."
  exit 1
fi

# Get subcommand
subcmds="$(cd "${run_dir}" && "${SPECINVOKE}" -n 2>&1 | grep -v "^#" | grep -v "^timer" | grep -v "^$")"
cmd_raw=$(echo "${subcmds}" | sed -n "${subcmd}p")
if [ -z "${cmd_raw}" ]; then
  echo "Error: Subcommand ${subcmd} not found for ${benchmark}"
  exit 1
fi

# Find SimPoint files
simpoint_file="${simpoint_output_dir}/bbv_${subcmd}.out.*.simpoints"
weights_file="${simpoint_output_dir}/bbv_${subcmd}.out.*.weights"
simpoint_files=$(ls $simpoint_file 2>/dev/null | head -1)
weights_files=$(ls $weights_file 2>/dev/null | head -1)

if [ -z "$simpoint_files" ] || [ -z "$weights_files" ]; then
  echo "Error: SimPoint files not found for subcmd ${subcmd}"
  exit 1
fi

# Find weight for this simpoint
# SimPoints file format: <simpoint_index> <cluster_id>
# Weights file format: <weight> <cluster_id>
# We need to find the cluster_id for this simpoint_index, then get the weight
cluster_id=$(awk -v sp="$simpoint" '$1 == sp {print $2; exit}' "$simpoint_files")
if [ -z "$cluster_id" ]; then
  echo "Error: SimPoint ${simpoint} not found in ${simpoint_files}"
  exit 1
fi
weight=$(awk -v cid="$cluster_id" '$2 == cid {print $1; exit}' "$weights_files")
if [ -z "$weight" ]; then
  echo "Error: Weight not found for cluster_id ${cluster_id} in ${weights_files}"
  exit 1
fi

echo "Found SimPoint ${simpoint} with weight ${weight}"

# Prepare directories
mkdir -p "${sift_output_dir}"
sift_dir_abs="$(cd "${sift_output_dir}" && pwd)"
sift_subcmd_dir="${sift_dir_abs}/subcmd_${subcmd}"
mkdir -p "$sift_subcmd_dir"

# Create parent directory structure
run_base_dir="${sift_subcmd_dir}/run_base_ref_gcc.0000"
if [ ! -d "$run_base_dir" ]; then
  cp -r "$run_dir" "$run_base_dir" 2>/dev/null || true
fi

# Clean command
# Remove redirects and clean up command line
# Use awk for safer string processing
cmd_clean=$(printf "%s\n" "$cmd_raw" | awk '{
  # Remove redirect patterns: " [0-9]*>>* *[^ ]*"
  gsub(/ [0-9]*>>* *[^ ]*/, "")
  print
}')
cmd_suffix=$(echo "$cmd_clean" | awk '{$1=""; sub(/^[ \t]+/, ""); print}')
cmd_suffix_noL=$(echo "$cmd_suffix" | awk '{gsub(/^-L [^ ]* /, ""); gsub(/^[ \t]+/, ""); print}')

# Set up environment
sniper_vm_ld_path="$SNIPER_SIM_LD_PATH"
original_ld_path="$LD_LIBRARY_PATH"
sniper_script_ld_path="$original_ld_path"

# Calculate fast_forward_target
interval="$SIMPOINT_INTERVAL"
fast_forward_target=$((simpoint * interval))
detailed_target="${interval}"
echo "[${benchmark} SIFT subcmd=${subcmd} simpoint=${simpoint}] SIMPOINT_INTERVAL=${interval}, fast_forward_target=${fast_forward_target}, detailed_target=${detailed_target}"

# Create execution directory
simpoint_run_dir="${sift_subcmd_dir}/run_dir_simpoint_${simpoint}"
mkdir -p "$simpoint_run_dir"

# Copy RUN_DIR contents if needed
if [ ! -f "${simpoint_run_dir}/.copied" ]; then
  if [ -d "${run_dir}" ]; then
    if [ "$(ls -A "${run_dir}" 2>/dev/null)" ]; then
      cp -r "${run_dir}"/* "${simpoint_run_dir}/" 2>&1 || {
        echo "Warning: Failed to copy some files from ${run_dir} to ${simpoint_run_dir}" >&2;
      };
    fi;
    touch "${simpoint_run_dir}/.copied";
  else
    echo "Error: RUN_DIR ${run_dir} does not exist" >&2;
    exit 1;
  fi;
fi;

# Generate SIFT
output_base="${sift_subcmd_dir}/simpoint_${simpoint}"
response_file="${output_base}_response.app0.th0.sift"
mkdir -p "$(dirname "$response_file")"
touch "$response_file"

echo "[${benchmark} SIFT subcmd=${subcmd} simpoint=${simpoint}] Generating SIFT..."

cd "${simpoint_run_dir}" && \
SNIPER_ROOT="${SNIPER_ROOT}" \
GRAPHITE_ROOT="${SNIPER_ROOT}" \
PIN_HOME="${PIN_HOME}" \
PIN_LD_RESTORE_REQUIRED=1 \
PIN_VM_LD_LIBRARY_PATH="${sniper_vm_ld_path}" \
PIN_APP_LD_LIBRARY_PATH="${original_ld_path}" \
SNIPER_SCRIPT_LD_LIBRARY_PATH="${sniper_script_ld_path}" \
LD_LIBRARY_PATH="${sniper_vm_ld_path}" \
LD_PRELOAD= \
QEMU_CPU="${QEMU_CPU_OPTIONS}" \
"${QEMU}" ${QEMU_FLAGS} -plugin "${QEMU_FRONTEND_PLUGIN}",verbose=on,response_files=on,fast_forward_target=${fast_forward_target},detailed_target=${detailed_target},output_file="${output_base}" ${cmd_suffix_noL} \
> "${output_base}.log" 2>&1

if [ ! -f "${output_base}.app0.th0.sift" ]; then
  echo "Error: SIFT file generation failed. Check log: ${output_base}.log"
  exit 1
fi

echo "[${benchmark} SIFT subcmd=${subcmd} simpoint=${simpoint}] SIFT generation completed"

# Run Sniper
sift_file="${output_base}.app0.th0.sift"
simulation_output_dir="${SIMULATION_DIR}/${benchmark}"
sniper_subcmd_dir="${simulation_output_dir}/subcmd_${subcmd}"
mkdir -p "${sniper_subcmd_dir}"

sift_basename="simpoint_${simpoint}.app0.th0"
output_subdir="${sniper_subcmd_dir}/${sift_basename}"

echo "[${benchmark} Sniper subcmd=${subcmd} simpoint=${simpoint}] Running simulation..."

# Calculate roi-icount parameters
WARMUP_LENGTH=$((SIMPOINT_INTERVAL * 20 / 100))
DETAILED_LENGTH=$((SIMPOINT_INTERVAL * 80 / 100))
ROI_ICOUNT_PARAMS="0:${WARMUP_LENGTH}:${DETAILED_LENGTH}"

# Create output directory
mkdir -p "${output_subdir}"

# Run Sniper
# Ensure output_subdir is absolute path
mkdir -p "${output_subdir}"
output_subdir_abs="$(cd "${output_subdir}" && pwd)"
cd "${output_subdir_abs}"
RUN_SNIPER="${SNIPER_ROOT}/run-sniper"
CONFIG_BASE="${SNIPER_CONFIG_DIR}/riscv.cfg"
LOG_FILE="${output_subdir_abs}/sniper.log"

"${RUN_SNIPER}" \
  -v \
  -c "${CONFIG_BASE}" \
  --roi-script \
  -s "roi-icount:${ROI_ICOUNT_PARAMS}" \
  -c "general/magic=false" \
  -c "general/app=${benchmark}" \
  -c "perf_model/core/rob_timer/vec_physical_registers=40" \
  -c "perf_model/core/rob_timer/vec_reserve_policy=alloc_none" \
  -c "perf_model/dram/latency=200" \
  -c "perf_model/l1_dcache/outstanding_misses=48" \
  -c "perf_model/l2_cache/outstanding_misses=9" \
  --traces="${sift_file}" \
  > "${LOG_FILE}" 2>&1

if [ ! -f "${output_subdir_abs}/sim.out" ]; then
  echo "Error: Sniper simulation failed. Check log: ${LOG_FILE}"
  exit 1
fi

echo "[${benchmark} Sniper subcmd=${subcmd} simpoint=${simpoint}] Simulation completed"

# Convert SQLite to JSON/YAML if needed
if [ -f "${output_subdir_abs}/sim.stats.sqlite3" ]; then
  SQLITE_OUTPUT_FORMAT="${SQLITE_OUTPUT_FORMAT:-json}" \
  "${SCRIPT_DIR}/convert_sniper_sqlite.py" \
    "${output_subdir_abs}/sim.stats.sqlite3" \
    --format "${SQLITE_OUTPUT_FORMAT:-json}" \
    > "${output_subdir_abs}/sim.stats.${SQLITE_OUTPUT_FORMAT:-json}" 2>&1 || {
    echo "Warning: Failed to convert SQLite to ${SQLITE_OUTPUT_FORMAT:-json}" >&2;
  }
fi

# Clean up SIFT files to save disk space
echo "[${benchmark} Cleanup subcmd=${subcmd} simpoint=${simpoint}] Removing SIFT files..."
rm -f "${output_base}.app0.th0.sift" "${output_base}_response.app0.th0.sift" "${output_base}.log"
rm -rf "${simpoint_run_dir}"

echo "[${benchmark} Completed subcmd=${subcmd} simpoint=${simpoint}] All done"

