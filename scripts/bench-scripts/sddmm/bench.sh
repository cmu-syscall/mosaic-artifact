#!/bin/bash
set -euo pipefail

export PATH_TO_MOSAIC_ARTIFACT="${PATH_TO_MOSAIC_ARTIFACT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
result_dir="$PATH_TO_MOSAIC_ARTIFACT/scripts/bench-scripts/sddmm/result"
mkdir -p "$result_dir"
systems=("mkl" "gsl" "dot_blas" "taco" "blas" "tblis" "gemv_blas")
# Optional arguments allow a failed implementation to be retried on its own.
if (( $# )); then
    systems=("$@")
fi

for system in "${systems[@]}"; do
    export INCLUDE_PATH=" -I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib"
    export LIB_PATH=""
    export INCLUDE_HEADERS=""
    export DYNAMIC_LIB_FILES=""
    case "$system" in
        mkl)
            INCLUDE_PATH+=" -I/usr/include/mkl"
            INCLUDE_HEADERS='#include <mkl.h>
void sgemm_mkl_internal(int dim, float *a, float *b, float *c) {
    MKL_INT n = dim;
    float alpha = 1, beta = 0;
    sgemm("n", "n", &n, &n, &n, &alpha, a, &n, b, &n, &beta, c, &n);
}'
            DYNAMIC_LIB_FILES="-lmkl_rt"
            ;;
        gsl)
            INCLUDE_HEADERS='#include <gsl/gsl_blas.h>
void set_gsl_mat_data_row_major_s(gsl_matrix_float *mat, float *data) {
    mat->data = data;
}'
            DYNAMIC_LIB_FILES="-lgsl -lgslcblas"
            ;;
        blas|dot_blas|gemv_blas)
            INCLUDE_HEADERS='#include <cblas.h>'
            DYNAMIC_LIB_FILES="-lopenblas"
            ;;
        tblis)
            tblis_prefix="$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib/tblis"
            INCLUDE_PATH+=" -D_GNU_SOURCE -I$tblis_prefix/include -I$tblis_prefix/include/tblis"
            LIB_PATH="-L$tblis_prefix/lib -Wl,-rpath,$tblis_prefix/lib"
            INCLUDE_HEADERS='#include <tblis.h>
#include "tblis-wrappers.h"'
            DYNAMIC_LIB_FILES="-ltblis"
            ;;
        taco) ;;
        *) echo "Unknown Fig. 19 system: $system" >&2; exit 2 ;;
    esac
    "$PATH_TO_MOSAIC_ARTIFACT/mosaic/build/bin/taco-bench" \
        --benchmark_filter="^bench_sddmm_${system}/" \
        --benchmark_format=json --benchmark_out="$result_dir/$system"
done
