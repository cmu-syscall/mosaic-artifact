#!/bin/bash
systems=("stardust")

for i in "${systems[@]}"
do
    source "$PATH_TO_MOSAIC_ARTIFACT/scripts/mosaic_env_var.sh" "$i" || exit 1
    $PATH_TO_MOSAIC_ARTIFACT/mosaic/build/bin/./taco-bench --benchmark_filter=bench_spmv_$i  --benchmark_format=json --benchmark_out=$PATH_TO_MOSAIC_ARTIFACT/scripts/bench-scripts/spmv/result/$i
done