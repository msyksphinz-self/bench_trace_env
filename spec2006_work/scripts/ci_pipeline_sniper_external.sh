#!/usr/bin/env bash
# CI pipeline for daily SPEC performance evaluation using pre-generated external SIFT files.
# Skips QEMU, BBV, SimPoint, and SIFT generation — runs only Sniper + IPC estimation.
#
# Usage:
#   ./scripts/ci_pipeline_sniper_external.sh [--phase 1|2]
#
# Env:
#   EXTERNAL_SIFT_DIR      - Path to pre-generated SIFT files (default: Makefile value)
#   EXTERNAL_SIMPOINT_DIR  - Path to SimPoint weights (default: Makefile value)
#   NPROC                  - Parallel jobs (default: nproc/2)
#   BENCHMARKS             - Space-separated benchmark list (default: all)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC2006_WORK="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_BENCHMARKS="400.perlbench 401.bzip2 403.gcc 429.mcf 445.gobmk 456.hmmer 458.sjeng 462.libquantum 464.h264ref 471.omnetpp 473.astar 483.xalancbmk"
BENCHMARKS="${BENCHMARKS:-$DEFAULT_BENCHMARKS}"
NPROC="${NPROC:-$(($(nproc 2>/dev/null || echo 2) / 2))}"

RUN_PHASE_1=false
RUN_PHASE_2=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      shift
      case "${1:-}" in
        1) RUN_PHASE_1=true ;;
        2) RUN_PHASE_2=true ;;
        *) echo "Usage: $0 [--phase 1|2]. Unknown phase: $1" >&2; exit 1 ;;
      esac
      shift
      ;;
    *)
      echo "Usage: $0 [--phase 1|2]" >&2
      exit 1
      ;;
  esac
done

if ! $RUN_PHASE_1 && ! $RUN_PHASE_2; then
  RUN_PHASE_1=true
  RUN_PHASE_2=true
fi

cd "$SPEC2006_WORK"

echo "=== Daily SPEC Benchmark CI (External SIFT) ==="
echo "BENCHMARKS: $BENCHMARKS"
echo "NPROC: $NPROC"
echo "EXTERNAL_SIFT_DIR: ${EXTERNAL_SIFT_DIR:-(Makefile default)}"
echo "EXTERNAL_SIMPOINT_DIR: ${EXTERNAL_SIMPOINT_DIR:-(Makefile default)}"

# Phase 1: ensure Sniper is built, then run Sniper simulations with external SIFT files.
# EXTERNAL_SIFT_DIR is picked up by make via ?= (set in env or use Makefile default).
phase1() {
  echo "=== Phase 1: build Sniper (if needed) + run Sniper with external SIFT ==="
  make build_sniper

  SNIPER_TARGETS=$(echo "$BENCHMARKS" | tr ' ' '\n' | sed 's/^/run_sniper_external_/' | tr '\n' ' ')
  # shellcheck disable=SC2086
  make $SNIPER_TARGETS -j"$NPROC" || {
    echo "Warning: Some Sniper simulations failed" >&2
  }
  echo "=== Phase 1 done ==="
}

# Phase 2: estimate IPC using external SimPoint weights + print report.
# EXTERNAL_SIMPOINT_DIR is picked up by make via ?=.
phase2() {
  echo "=== Phase 2: Estimate IPC (external SimPoint weights) ==="
  IPC_TARGETS=$(echo "$BENCHMARKS" | tr ' ' '\n' | sed 's/^/estimate_ipc_external_/' | tr '\n' ' ')
  # shellcheck disable=SC2086
  make $IPC_TARGETS -j"$NPROC" || {
    echo "Warning: Some IPC estimations failed" >&2
  }
  make report_ipc || true
  echo "=== Phase 2 done ==="
}

if $RUN_PHASE_1; then phase1; fi
if $RUN_PHASE_2; then phase2; fi

echo "=== Daily CI pipeline completed ==="
