#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: SIMPOINT_DIR=... SIMULATION_DIR=... $0 <benchmark>" >&2
  echo "" >&2
  echo "This script estimates the overall IPC of a benchmark by computing" >&2
  echo "the weighted average of IPCs from all SimPoint simulations." >&2
  exit 1
fi

benchmark="$1"

: "${SIMPOINT_DIR:?SIMPOINT_DIR is required}"
: "${SIMULATION_DIR:?SIMULATION_DIR is required}"

simpoint_dir="${SIMPOINT_DIR}/${benchmark}"
simulation_dir="${SIMULATION_DIR}/${benchmark}"

echo "=== Estimating IPC for ${benchmark} ==="

# Check if directories exist
if [ ! -d "${simpoint_dir}" ]; then
  echo "Error: SimPoint directory ${simpoint_dir} not found." >&2
  echo "Please run 'make run_simpoint_${benchmark}' first." >&2
  exit 1
fi

if [ ! -d "${simulation_dir}" ]; then
  echo "Error: Simulation directory ${simulation_dir} not found." >&2
  echo "Please run 'make run_sniper_${benchmark}' first." >&2
  exit 1
fi

# Find all weights files
weights_files=$(find "${simpoint_dir}" -type f -name "*.weights" | sort)

if [ -z "${weights_files}" ]; then
  echo "Error: No weights files found in ${simpoint_dir}." >&2
  exit 1
fi

# Output CSV header
output_csv="${simulation_dir}/ipc_estimation.csv"
echo "subcmd,simpoint,weight,ipc,weighted_ipc" > "${output_csv}"

# Process each weights file
total_weighted_ipc=0.0
total_weight=0.0
num_simpoints=0

echo ""
echo "Processing SimPoint results..."
echo ""

while IFS= read -r weights_file; do
  # Extract subcmd number from filename (e.g., bbv_1.out.0.weights -> 1)
  basename_weights=$(basename "${weights_file}")
  subcmd=$(echo "${basename_weights}" | grep -oP '^bbv_\K[0-9]+' || echo "")

  if [ -z "${subcmd}" ]; then
    echo "Warning: Could not extract subcmd from ${weights_file}, skipping" >&2
    continue
  fi

  # Find corresponding simpoints file
  simpoints_file="${weights_file%.weights}.simpoints"
  if [ ! -f "${simpoints_file}" ]; then
    echo "Warning: SimPoints file not found: ${simpoints_file}" >&2
    continue
  fi

  # Create associative arrays to map cluster_id to simpoint_index and weight
  declare -A cluster_to_simpoint
  declare -A cluster_to_weight

  # Read simpoints file: <simpoint_index> <cluster_id>
  while read -r simpoint_idx cluster_id rest; do
    # Skip empty lines or comments
    if [ -z "${simpoint_idx}" ] || [[ "${simpoint_idx}" =~ ^# ]]; then
      continue
    fi
    cluster_to_simpoint[$cluster_id]=$simpoint_idx
  done < "${simpoints_file}"

  # Read weights file: <weight> <cluster_id>
  while read -r weight cluster_id rest; do
    # Skip empty lines or comments
    if [ -z "${weight}" ] || [[ "${weight}" =~ ^# ]]; then
      continue
    fi
    cluster_to_weight[$cluster_id]=$weight
  done < "${weights_file}"

  # Process each cluster
  for cluster_id in "${!cluster_to_simpoint[@]}"; do
    simpoint_idx="${cluster_to_simpoint[$cluster_id]}"
    weight="${cluster_to_weight[$cluster_id]}"

    if [ -z "${weight}" ]; then
      echo "Warning: No weight found for cluster ${cluster_id}" >&2
      continue
    fi

    # Find corresponding simulation output
    # Actual layout: sniper_results/<benchmark>/subcmd_<N>/simpoint_<idx>/sim.out
    sim_out_path="${simulation_dir}/subcmd_${subcmd}/simpoint_${simpoint_idx}/sim.out"

    if [ ! -f "${sim_out_path}" ]; then
      echo "Warning: Simulation output not found: ${sim_out_path}" >&2
      continue
    fi

    # Extract IPC from sim.out (line containing "IPC")
    ipc=$(grep -m1 "^  IPC" "${sim_out_path}" | awk '{print $NF}')

    if [ -z "${ipc}" ]; then
      echo "Warning: Could not extract IPC from ${sim_out_path}" >&2
      continue
    fi

    # Calculate weighted IPC
    weighted_ipc=$(echo "${ipc} * ${weight}" | bc -l)

    # Add to CSV
    echo "${subcmd},${simpoint_idx},${weight},${ipc},${weighted_ipc}" >> "${output_csv}"

    # Update totals
    total_weighted_ipc=$(echo "${total_weighted_ipc} + ${weighted_ipc}" | bc -l)
    total_weight=$(echo "${total_weight} + ${weight}" | bc -l)
    num_simpoints=$((num_simpoints + 1))

    printf "  [subcmd %s] SimPoint %5s: IPC=%.4f, Weight=%.6f, Weighted_IPC=%.6f\n" \
           "${subcmd}" "${simpoint_idx}" "${ipc}" "${weight}" "${weighted_ipc}"
  done

  # Clean up associative arrays
  unset cluster_to_simpoint
  unset cluster_to_weight

done <<< "${weights_files}"

echo ""
echo "=== Results ==="
echo "Total SimPoints processed: ${num_simpoints}"
echo "Total weight sum: ${total_weight}"

if (( $(echo "${total_weight} > 0" | bc -l) )); then
  overall_ipc=$(echo "scale=6; ${total_weighted_ipc} / ${total_weight}" | bc -l)
  echo ""
  echo "======================================"
  echo "Estimated Overall IPC: ${overall_ipc}"
  echo "======================================"
  echo ""

  # Save summary
  summary_file="${simulation_dir}/ipc_summary.txt"
  {
    echo "Benchmark: ${benchmark}"
    echo "Total SimPoints: ${num_simpoints}"
    echo "Total Weight Sum: ${total_weight}"
    echo "Estimated Overall IPC: ${overall_ipc}"
    echo ""
    echo "Detailed results saved to: ${output_csv}"
  } > "${summary_file}"

  echo "Summary saved to: ${summary_file}"
  echo "Detailed CSV saved to: ${output_csv}"
else
  echo "Error: Total weight is zero or invalid." >&2
  exit 1
fi

echo ""
echo "=== Completed IPC estimation for ${benchmark} ==="
