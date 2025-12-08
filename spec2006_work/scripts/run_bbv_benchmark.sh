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
scripts_dir="${output_dir_abs}/scripts"
mkdir -p "${scripts_dir}"

export BENCHMARK="${benchmark}" NUM_SUBCMDS="${num_subcmds}" RUN_DIR="${run_dir}" BIN_QEMU="${QEMU}" BBV_PLUGIN="${BBV_PLUGIN}"

echo "=== Generating shell scripts for ${benchmark} with BBV ==="
echo "${subcmds}" | awk '{print NR "\t" $0}' | while IFS=$'\t' read -r idx cmd; do
  cmd_clean=$(echo "${cmd}" | sed 's| [0-9]*>>* *[^ ]*||g')
  bbv_file="${bbv_dir_abs}/bbv_${idx}.out"
  output_file="${output_dir_abs}/output_${idx}.txt"
  script_file="${scripts_dir}/run_${idx}.sh"
  
  # BBVプラグイン付きコマンドの生成
  cmd_with_bbv=$(echo "${cmd_clean}" | sed "s|${QEMU}|${QEMU} -plugin ${BBV_PLUGIN},outfile=${bbv_file},interval=${SIMPOINT_INTERVAL}|")
  
  cat > "${script_file}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

BENCHMARK="${benchmark}"
RUN_DIR="${run_dir}"
BBV_FILE="${bbv_file}"
OUTPUT_FILE="${output_file}"

echo "[${BENCHMARK} BBV ${idx}/${num_subcmds}] Starting..."
(cd "\${RUN_DIR}" && eval "${cmd_with_bbv}" > "\${OUTPUT_FILE}" 2>&1) && \
echo "[${BENCHMARK} BBV ${idx}/${num_subcmds}] Completed - BBV saved to \${BBV_FILE}" || \
echo "[${BENCHMARK} BBV ${idx}/${num_subcmds}] Failed"
EOF
  chmod +x "${script_file}"
  echo "Generated: ${script_file}"
done

echo "=== Executing scripts in parallel ==="
find "${scripts_dir}" -name "run_*.sh" -type f | sort -V | \
parallel --line-buffer -j "${num_subcmds}" bash '{}'

echo "=== Completed all ${benchmark} BBV collection ==="
