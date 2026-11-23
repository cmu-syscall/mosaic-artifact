#!/bin/bash
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
artifact=${PATH_TO_MOSAIC_ARTIFACT:-$(cd -- "$script_dir/../../.." && pwd)}
systems=("taco_scheduled" "optimized" "cpu_blocked" "dot_mkl" "mkl" "taco" "blas" "gemv_mkl" "tblis" "gemv_gsl" "sampled_gsl")
if [[ $# -gt 0 ]]; then
    systems=("$@")
fi

for i in "${systems[@]}"
do
    source "$artifact/scripts/mosaic_env_var.sh" "$i" || exit 1
    "$artifact/mosaic/build/bin/taco-bench" \
        --benchmark_filter="^bench_sddmm_varySparisty_${i}/" \
        --benchmark_format=json \
        --benchmark_out="$script_dir/result/$i" || exit 1
done

if [[ $# -gt 0 ]]; then
    exit 0
fi

if [[ -x "$artifact/mosaic/build/bin/taco-bench-sddmm-cusparse" ]]; then
    PATH_TO_MOSAIC_ARTIFACT="$artifact" bash "$script_dir/bench-cusparse.sh" || exit 1
else
    echo "Skipping Figure 16 cuSPARSE benchmark. Enable MOSAIC_CUSPARSE_SDDMM to build it."
fi

if [[ -x "$artifact/mosaic/build/bin/taco-bench-sddmm-cuda" ]]; then
    PATH_TO_MOSAIC_ARTIFACT="$artifact" bash "$script_dir/bench-cusparse.sh" cuda_optimized || exit 1
    PATH_TO_MOSAIC_ARTIFACT="$artifact" bash "$script_dir/bench-cusparse.sh" cuda_row_tiled || exit 1
else
    echo "Skipping Figure 16 optimized CUDA benchmark. Enable MOSAIC_CUDA_SDDMM to build it."
fi
