#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: SNIPER_ROOT=... SIFT_DIR=... SIMULATION_DIR=... CONFIG_DIR=... SIMPOINT_INTERVAL=... $0 <benchmark> [config_options...]" >&2
  exit 1
fi

benchmark="$1"
shift 1
extra_config_options="$@"

: "${SNIPER_ROOT:?SNIPER_ROOT is required}"
: "${SIFT_DIR:?SIFT_DIR is required}"
: "${SIMULATION_DIR:?SIMULATION_DIR is required}"
: "${CONFIG_DIR:?CONFIG_DIR is required}"
: "${SIMPOINT_INTERVAL:?SIMPOINT_INTERVAL is required}"

# Convert to absolute paths to ensure they work even if directory changes
sift_output_dir=$(cd "${SIFT_DIR}/${benchmark}" 2>/dev/null && pwd || echo "${SIFT_DIR}/${benchmark}")
simulation_output_dir=$(cd "${SIMULATION_DIR}/${benchmark}" 2>/dev/null && pwd || echo "${SIMULATION_DIR}/${benchmark}")

echo "=== Running Sniper simulations for ${benchmark} ==="

if [ ! -d "${sift_output_dir}" ]; then
  echo "Error: SIFT directory ${sift_output_dir} not found. Please run 'make run_sift_${benchmark}' first."
  exit 1
fi

# Find all SIFT files in the benchmark directory and convert to absolute paths
# Look for files matching pattern: subcmd_*/simpoint_*.sift
if command -v realpath > /dev/null 2>&1; then
  sift_files=$(find "${sift_output_dir}" -type f -name "*.sift" | grep -v "_response" | while read -r f; do realpath "$f"; done | sort)
else
  # Fallback: use find with absolute path (results are already absolute if starting dir is absolute)
  sift_files=$(find "${sift_output_dir}" -type f -name "*.sift" | grep -v "_response" | sort)
fi

if [ -z "${sift_files}" ]; then
  echo "Error: No SIFT files found in ${sift_output_dir}. Please run 'make run_sift_${benchmark}' first."
  exit 1
fi

num_sift_files=$(echo "${sift_files}" | wc -l)
echo "Found ${num_sift_files} SIFT file(s) for ${benchmark}"

# Create simulation output directory
mkdir -p "${simulation_output_dir}"

# Get script directory
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SQLite conversion script and format (default: json)
CONVERT_SQLITE_SCRIPT="${script_dir}/convert_sniper_sqlite.py"
SQLITE_OUTPUT_FORMAT="${SQLITE_OUTPUT_FORMAT:-json}"

# Export environment variables for the script
export SNIPER_ROOT SIFT_DIR SIMULATION_DIR CONFIG_DIR SIMPOINT_INTERVAL SQLITE_OUTPUT_FORMAT
BENCHMARK="${benchmark}"
SCRIPT_DIR="${script_dir}"
EXTRA_CONFIG_OPTIONS="${extra_config_options}"

# Convert to absolute paths
simulation_dir_abs="$(cd "${simulation_output_dir}" 2>/dev/null && pwd || echo "${simulation_output_dir}")"

# All script list file
all_script_list_file="${simulation_dir_abs}/.all_script_list.txt"
rm -f "$all_script_list_file"

# Generate executable scripts for each SIFT file
echo "Generating executable scripts for each SimPoint..."
while IFS= read -r sift_file; do
  # Convert to absolute path
  if command -v realpath > /dev/null 2>&1; then
    sift_file_abs=$(realpath "${sift_file}")
  else
    sift_file_abs=$(cd "$(dirname "${sift_file}")" 2>/dev/null && pwd)/$(basename "${sift_file}") || echo "${sift_file}"
  fi

  # Extract subcmd directory name (e.g., subcmd_1)
  # Try Perl regex first, fallback to sed if not available
  if echo "${sift_file_abs}" | grep -oP 'subcmd_\K[0-9]+' > /dev/null 2>&1; then
    subcmd_dir=$(echo "${sift_file_abs}" | grep -oP 'subcmd_\K[0-9]+')
  else
    subcmd_dir=$(echo "${sift_file_abs}" | sed -n 's|.*subcmd_\([0-9]\+\).*|\1|p')
  fi
  if [ -z "${subcmd_dir}" ]; then
    echo "Warning: Could not extract subcmd from ${sift_file}, skipping" >&2
    continue
  fi

  # Extract simpoint number from filename (e.g., simpoint_17.sift -> 17)
  sift_basename=$(basename "${sift_file}" .sift)
  if echo "${sift_basename}" | grep -oP 'simpoint_\K[0-9]+' > /dev/null 2>&1; then
    simpoint=$(echo "${sift_basename}" | grep -oP 'simpoint_\K[0-9]+')
  else
    simpoint=$(echo "${sift_basename}" | sed -n 's|simpoint_\([0-9]\+\).*|\1|p')
  fi
  if [ -z "${simpoint}" ]; then
    echo "Warning: Could not extract simpoint from ${sift_file}, skipping" >&2
    continue
  fi

  # Create subcmd directory in simulation output
  sniper_subcmd_dir="${simulation_dir_abs}/subcmd_${subcmd_dir}"
  mkdir -p "${sniper_subcmd_dir}"

  # Output subdirectory name (same as SIFT basename, in the same directory as the script)
  output_subdir="${sniper_subcmd_dir}/${sift_basename}"

  # Generate script file
  script_file="${sniper_subcmd_dir}/run_sniper_simpoint_${simpoint}.sh"

  # Calculate roi-icount parameters based on SIMPOINT_INTERVAL
  WARMUP_LENGTH=$((SIMPOINT_INTERVAL * 20 / 100))
  DETAILED_LENGTH=$((SIMPOINT_INTERVAL * 80 / 100))
  ROI_ICOUNT_PARAMS="0:${WARMUP_LENGTH}:${DETAILED_LENGTH}"

  # Escape extra_config_options for use in heredoc
  if [ -n "${extra_config_options}" ]; then
    # Use printf %q to properly escape arguments
    escaped_extra_opts=$(printf '%q ' ${extra_config_options})
  else
    escaped_extra_opts=""
  fi

  cat > "${script_file}" << EOF
#!/usr/bin/env bash
set -euo pipefail

echo "[${BENCHMARK} Sniper] Running simulation for SimPoint ${simpoint}";

# Create output directory
mkdir -p "${output_subdir}"

# Build run-sniper command
RUN_SNIPER="${SNIPER_ROOT}/run-sniper"
CONFIG_BASE="${CONFIG_DIR}/riscv.cfg"

# Default configuration options
DEFAULT_OPTIONS=(
  "-v"
  "-c" "\${CONFIG_BASE}"
  "--roi-script"
  "-s" "roi-icount:${ROI_ICOUNT_PARAMS}"
  "-c" "general/magic=false"
  "-c" "general/app=${BENCHMARK}"
  "-c" "perf_model/core/rob_timer/vec_physical_registers=40"
  "-c" "perf_model/core/rob_timer/vec_reserve_policy=alloc_none"
  "-c" "perf_model/dram/latency=200"
  "-c" "perf_model/l1_dcache/outstanding_misses=48"
  "-c" "perf_model/l2_cache/outstanding_misses=9"
  "--traces=${sift_file_abs}"
)

# Change to output directory and run simulation
cd "${output_subdir}"

log_file="${output_subdir}/sniper_run.log"

echo "[${BENCHMARK} Sniper] Running Sniper simulation with SIFT file: ${sift_file_abs}"
echo "[${BENCHMARK} Sniper] Output directory: ${output_subdir}"
echo "[${BENCHMARK} Sniper] Saving execution log to: \${log_file}"

"\${RUN_SNIPER}" -d "${output_subdir}" "\${DEFAULT_OPTIONS[@]}" ${escaped_extra_opts} 2>&1 | tee "\${log_file}"

if [ \${PIPESTATUS[0]} -eq 0 ]; then
  echo "[${BENCHMARK} Sniper] Completed SimPoint ${simpoint}: ${output_subdir}"

  # Convert sim.stats.sqlite3 to JSON/YAML if it exists
  sqlite_file="${output_subdir}/sim.stats.sqlite3"
  if [ -f "\${sqlite_file}" ]; then
    echo "[${BENCHMARK} Sniper] Converting sqlite3 to ${SQLITE_OUTPUT_FORMAT}..."
    if [ -f "${CONVERT_SQLITE_SCRIPT}" ]; then
      python3 "${CONVERT_SQLITE_SCRIPT}" "\${sqlite_file}" --format "${SQLITE_OUTPUT_FORMAT}" || {
        echo "[${BENCHMARK} Sniper] Warning: Failed to convert sqlite3 file" >&2
      }
    else
      echo "[${BENCHMARK} Sniper] Warning: Conversion script not found: ${CONVERT_SQLITE_SCRIPT}" >&2
    fi
  else
    echo "[${BENCHMARK} Sniper] Warning: sim.stats.sqlite3 not found in ${output_subdir}" >&2
  fi
else
  echo "[${BENCHMARK} Sniper] Failed SimPoint ${simpoint}: ${output_subdir} (check \${log_file})" >&2
  exit 1
fi
EOF
  chmod +x "${script_file}"
  echo "${script_file}" >> "${all_script_list_file}"

done <<< "${sift_files}"

# Run all generated scripts in parallel
if [ -f "${all_script_list_file}" ] && [ -s "${all_script_list_file}" ]; then
  num_scripts=$(wc -l < "${all_script_list_file}")
  echo "Generated ${num_scripts} executable script(s)"

  if command -v parallel > /dev/null 2>&1; then
    echo "Running simulations in parallel..."
    # Limit parallel jobs to avoid file handle issues
    PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc)}"
    if [ "$PARALLEL_JOBS" -gt 252 ]; then
      PARALLEL_JOBS=252
    fi
    cat "${all_script_list_file}" | \
    parallel --line-buffer -j "${PARALLEL_JOBS}" '{}' || {
      echo "Warning: Some simulations failed" >&2
    }
  else
    echo "Running simulations sequentially (parallel command not available)..."
    while IFS= read -r script_file; do
      "${script_file}" || {
        echo "Warning: Simulation failed: ${script_file}" >&2
      }
    done < "${all_script_list_file}"
  fi
else
  echo "Error: No scripts were generated" >&2
  exit 1
fi

echo "=== Completed Sniper simulations for ${benchmark} ==="
