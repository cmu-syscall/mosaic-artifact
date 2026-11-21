#!/bin/bash
systems=("dot_mkl" "mkl" "taco" "blas" "gemv_mkl" "tblis" "gemv_gsl")

for i in "${systems[@]}"
do
    source "$PATH_TO_MOSAIC_ARTIFACT/scripts/mosaic_env_var.sh" "$i" || exit 1
    $PATH_TO_MOSAIC_ARTIFACT/mosaic/build/bin/./taco-bench --benchmark_filter=bench_sddmm_varySparisty_$i  --benchmark_format=json --benchmark_out=$PATH_TO_MOSAIC_ARTIFACT/scripts/bench-scripts/sddmm_varSparsity/result/$i
done