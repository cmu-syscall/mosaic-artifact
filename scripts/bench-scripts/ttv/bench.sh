#!/bin/bash
systems=("taco" "tblis" "gsl" "blas" "mkl")

for i in "${systems[@]}"
do
    source "$PATH_TO_MOSAIC_ARTIFACT/scripts/mosaic_env_var.sh" "$i" || exit 1
    $PATH_TO_MOSAIC_ARTIFACT/mosaic/build/bin/./taco-bench --benchmark_filter=bench_ttv_$i  --benchmark_format=json --benchmark_out=$PATH_TO_MOSAIC_ARTIFACT/scripts/bench-scripts/ttv/result/$i
done