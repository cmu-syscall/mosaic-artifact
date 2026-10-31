#!/bin/bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../mosaic_env_var.sh"

result_dir="$PATH_TO_MOSAIC_ARTIFACT/scripts/bench-scripts/sddmm/result"
mkdir -p "$result_dir"
systems=("mkl" "gsl" "dot_blas" "taco" "blas" "tblis" "gemv_blas")
if (( $# )); then
    systems=("$@")
fi

for i in "${systems[@]}"; do
    configure_mosaic_system "$i"
    "$PATH_TO_MOSAIC_ARTIFACT/mosaic/build/bin/taco-bench" \
        --benchmark_filter="^bench_sddmm_${i}/" \
        --benchmark_format=json --benchmark_out="$result_dir/$i"
done
