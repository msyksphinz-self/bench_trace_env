#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 8 ]; then
  echo "Usage: $0 <benchmark> <SPEC_ROOT> <SPECINVOKE> <RESULT_DIR> <BBV_DIR> <QEMU> <BBV_PLUGIN> <SIMPOINT_INTERVAL>" >&2
  exit 1
fi

benchmark="$1"
SPEC_ROOT="$2"
SPECINVOKE="$3"
RESULT_DIR="$4"
BBV_DIR="$5"
QEMU="$6"
BBV_PLUGIN="$7"
SIMPOINT_INTERVAL="$8"
run_dir="${SPEC_ROOT}/benchspec/CPU2006/${benchmark}/run/run_base_ref_gcc.0000"
bbv_output_dir="${BBV_DIR}/${benchmark}"
output_dir="${RESULT_DIR}/${benchmark}_bbv"

echo "=== Preparing BBV output directory for ${benchmark} ==="
mkdir -p "${bbv_output_dir}"
mkdir -p "${output_dir}"

subcmds="$(cd "${run_dir}" && "${SPECINVOKE}" -n 2>&1 | grep -v "^#" | grep -v "^timer" | grep -v "^$")"
num_subcmds="$(echo "${subcmds}" | wc -l)"
echo "=== Subcommands for ${benchmark} with BBV (${num_subcmds} commands)"

bbv_dir_abs="$(cd "${bbv_output_dir}" && pwd)"
output_dir_abs="$(cd "${output_dir}" && pwd)"
export bbv_dir_abs output_dir_abs

export BENCHMARK="${benchmark}" NUM_SUBCMDS="${num_subcmds}" RUN_DIR="${run_dir}" BIN_QEMU="${QEMU}" BBV_PLUGIN="${BBV_PLUGIN}"

echo "${subcmds}" | nl -nln | \
parallel --line-buffer --colsep '\t' -j "${num_subcmds}" '
cmd_clean=$(echo {2} | sed "s/ [0-9]*>>* *[^ ]*//g");
bbv_file="${bbv_dir_abs}/bbv_{1}.out";
output_file="${output_dir_abs}/output_{1}.txt";
cmd_with_bbv=$(echo "$cmd_clean" | sed "s|$BIN_QEMU|$BIN_QEMU -plugin $BBV_PLUGIN,outfile=$bbv_file,interval=$SIMPOINT_INTERVAL|");
echo "[$BENCHMARK BBV {1}/$NUM_SUBCMDS] Starting...";
(cd "$RUN_DIR" && eval "$cmd_with_bbv" > "$output_file" 2>&1) && \
echo "[$BENCHMARK BBV {1}/$NUM_SUBCMDS] Completed - BBV saved to $bbv_file" || \
echo "[$BENCHMARK BBV {1}/$NUM_SUBCMDS] Failed"
'

echo "=== Completed all ${benchmark} BBV collection ==="
