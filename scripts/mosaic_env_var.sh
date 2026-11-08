#!/bin/bash
# Source this file from Bash before running Mosaic benchmarks.
export PATH_TO_MOSAIC_ARTIFACT="${PATH_TO_MOSAIC_ARTIFACT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

# Select a provider when sourcing: source scripts/mosaic_env_var.sh tblis
# Reset all four kernel settings so a previous provider cannot leak into a run.
# Keep a leading space: module.cpp appends INCLUDE_PATH directly to -lm.
export INCLUDE_PATH=" "
export LIB_PATH=" "
export DYNAMIC_LIB_FILES=""
export INCLUDE_HEADERS=""

case "${1:-blas}" in
  blas|openblas|dot_blas|gemv_blas)
    export INCLUDE_HEADERS='#include <cblas.h>'
    export DYNAMIC_LIB_FILES="-lopenblas"
    ;;
  tblis)
    export INCLUDE_PATH=" -I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib -I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib/tblis/include -I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib/tblis/include/tblis"
    export LIB_PATH=" -L$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib/tblis/lib -Wl,-rpath,$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib/tblis/lib"
    export INCLUDE_HEADERS='#include "tblis.h"
#include "tblis-wrappers.h"'
    export DYNAMIC_LIB_FILES="-l:libtblis.so.0.0.0"
    ;;
  mkl|dot_mkl|gemv_mkl|bug_mkl)
    export INCLUDE_PATH=" -I$PATH_TO_MOSAIC_ARTIFACT/mosaic/include -I/usr/include/mkl -I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib"
    export INCLUDE_HEADERS='#include "taco/taco_tensor_t.h"
#include <mkl.h>
#include "mkl-wrappers.h"'
    export DYNAMIC_LIB_FILES="-Wl,--no-as-needed -lmkl_rt -lpthread -lm -ldl"
    ;;
  gsl|gemv_gsl)
    export INCLUDE_PATH=" -I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib -I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib/gsl/include"
    export LIB_PATH=" -L$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib/gsl/lib -Wl,-rpath,$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib/gsl/lib"
    export INCLUDE_HEADERS='#include <gsl/gsl_vector.h>
#include <gsl/gsl_blas.h>
#include "gsl-wrappers.h"'
    export DYNAMIC_LIB_FILES="-lgsl -lgslcblas -lm"
    ;;
  cuda)
    export INCLUDE_PATH=" -I/usr/local/cuda/include -I$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib"
    export LIB_PATH=" -L/usr/local/cuda/lib64 -Wl,-rpath,/usr/local/cuda/lib64"
    export INCLUDE_HEADERS='#include <cuda_runtime_api.h>
#include <cusparse.h>
#include "cuda-wrappers.h"'
    export DYNAMIC_LIB_FILES="-lcudart -lcusparse"
    ;;
  taco)
    ;;
  stardust)
    export INCLUDE_HEADERS='#include <time.h>'
    ;;
  *)
    echo "Unknown Mosaic provider: $1" >&2
    return 1
    ;;
esac

export TENSOR_ALGEBRA_SRC="$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_src"
export TENSOR_ALGEBRA_LIB="$PATH_TO_MOSAIC_ARTIFACT/tensor_algebra_systems_lib"
