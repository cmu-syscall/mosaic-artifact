#!/bin/bash
# Source this file to configure Mosaic's external libraries.
export PATH_TO_MOSAIC_ARTIFACT="${PATH_TO_MOSAIC_ARTIFACT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TENSOR_ALGEBRA_SRC="$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_src"
export TENSOR_ALGEBRA_LIB="$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib"

# BLAS providers share symbols and incompatible headers. Select one provider
# per process so a BLAS benchmark cannot silently resolve to another library.
configure_mosaic_system() {
    local system="${1:-tblis}"
    local tblis_prefix mkl_root
    export INCLUDE_PATH=" -I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib"
    export LIB_PATH=""
    export INCLUDE_HEADERS=""
    export DYNAMIC_LIB_FILES=""
    case "$system" in
        mkl)
            mkl_root="${MKLROOT:-}"
            if [[ -z "$mkl_root" && -r /opt/intel/oneapi/mkl/latest/include/mkl.h ]]; then
                mkl_root=/opt/intel/oneapi/mkl/latest
            fi
            if [[ -n "$mkl_root" ]]; then
                INCLUDE_PATH+=" -I$mkl_root/include"
                LIB_PATH="-L$mkl_root/lib/intel64 -Wl,-rpath,$mkl_root/lib/intel64"
            else
                INCLUDE_PATH+=" -I/usr/include/mkl"
            fi
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
            tblis_prefix="${TBLIS_ROOT:-$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib/tblis}"
            INCLUDE_PATH+=" -D_GNU_SOURCE -I$tblis_prefix/include -I$tblis_prefix/include/tblis"
            LIB_PATH="-L$tblis_prefix/lib -Wl,-rpath,$tblis_prefix/lib"
            INCLUDE_HEADERS='#include <tblis.h>
#include "tblis-wrappers.h"'
            DYNAMIC_LIB_FILES="-ltblis"
            ;;
        taco) ;;
        *) echo "Unknown Fig. 19 system: $system" >&2; exit 2 ;;
    esac
}

# Preserve the original default for callers that source this file directly.
configure_mosaic_system "${MOSAIC_SYSTEM:-tblis}"
