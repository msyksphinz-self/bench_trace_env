#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <benchmark> <SPEC_ROOT> <SPECINVOKE> <RESULT_DIR>" >&2
  exit 1
fi

benchmark="$1"
SPEC_ROOT="$2"
SPECINVOKE="$3"
RESULT_DIR="$4"

run_dir="${SPEC_ROOT}/benchspec/CPU2006/${benchmark}/run/run_base_ref_gcc.0000"
output_dir="${RESULT_DIR}/${benchmark}"

echo "=== Running ${benchmark} ==="
mkdir -p "${output_dir}"

subcmds="$(cd "${run_dir}" && "${SPECINVOKE}" -n 2>&1 | grep -v "^#" | grep -v "^timer" | grep -v "^$")"
num_subcmds="$(echo "${subcmds}" | wc -l)"
echo "=== Subcommands for ${benchmark} (${num_subcmds} commands)"

output_dir_abs="$(cd "${output_dir}" && pwd)"
scripts_dir="${output_dir_abs}/scripts"
mkdir -p "${scripts_dir}"

export BENCHMARK="${benchmark}" NUM_SUBCMDS="${num_subcmds}" RUN_DIR="${run_dir}"

echo "=== Generating shell scripts for ${benchmark} ==="
echo "${subcmds}" | awk '{print NR "\t" $0}' | while IFS=$'\t' read -r idx cmd; do
  cmd_clean=$(echo "${cmd}" | sed 's| [0-9]*>>* *[^ ]*||g')
  output_file="${output_dir_abs}/output_${idx}.txt"
  script_file="${scripts_dir}/run_${idx}.sh"
  
  cat > "${script_file}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

BENCHMARK="${benchmark}"
RUN_DIR="${run_dir}"
OUTPUT_FILE="${output_file}"

echo "[${BENCHMARK} ${idx}/${num_subcmds}] Starting..."
(cd "\${RUN_DIR}" && eval "${cmd_clean}" > "\${OUTPUT_FILE}" 2>&1) && \
echo "[${BENCHMARK} ${idx}/${num_subcmds}] Completed" || \
echo "[${BENCHMARK} ${idx}/${num_subcmds}] Failed"
EOF
  chmod +x "${script_file}"
  echo "Generated: ${script_file}"
done

echo "=== Executing scripts in parallel ==="
find "${scripts_dir}" -name "run_*.sh" -type f | sort -V | \
parallel --line-buffer -j "${num_subcmds}" bash '{}'

echo "=== Completed all ${benchmark} subcommands ==="


