#!/usr/bin/env bash

configure_mosaic_system() {
    local root="${PATH_TO_MOSAIC_ARTIFACT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local selection="${1:-${MOSAIC_LIBRARIES:-tblis,mkl}}"
    local library provider="" headers="" includes="-I$root/tensor_algebra_systems_lib"
    local paths="" libraries="" cuda="${CUDA_HOME:-/usr/local/cuda}"
    local tblis="${TBLIS_ROOT:-$root/tensor_algebra_systems_lib/tblis}"
    local cublas="${CUBLAS_ROOT:-$cuda}" cusparse="${CUSPARSE_ROOT:-$cuda}" prefix
    local -a selected
    local -A seen
    IFS=',' read -r -a selected <<< "$selection"
    if [[ -z "$selection" || "$selection" == *, ]]; then
        printf 'Specify libraries: taco, tblis, mkl, openblas, gsl, cuda\n' >&2
        return 2
    fi
    for library in "${selected[@]}"; do
        library="${library//[[:space:]]/}"
        case "$library" in blas|dot_blas|gemv_blas) library=openblas ;; esac
        [[ -n "$library" ]] || { printf 'Empty library selection\n' >&2; return 2; }
        [[ -z "${seen[$library]:-}" ]] || continue
        seen[$library]=1
        case "$library" in
            mkl|openblas|gsl)
                if [[ -n "$provider" && "$provider" != "$library" ]]; then
                    printf 'Choose only one CBLAS provider: mkl, openblas, or gsl\n' >&2
                    return 2
                fi
                provider="$library" ;;
        esac
        case "$library" in
            taco) ;;
            tblis)
                test -f "$tblis/include/tblis/tblis.h" || {
                    printf 'Set TBLIS_ROOT to an installed TBLIS prefix (currently %s)\n' "$tblis" >&2
                    return 2
                }
                headers+=$'#include <tblis.h>\n#include "tblis-wrappers.h"\n'
                includes+=" -I$tblis/include -I$tblis/include/tblis"
                paths+=" -L$tblis/lib -Wl,-rpath,$tblis/lib"
                libraries+=" -ltblis" ;;
            mkl)
                test -f /usr/include/mkl/mkl.h || { printf 'MKL development files are missing\n' >&2; return 2; }
                headers+=$'#include <mkl.h>\n#include "mkl-wrappers.h"\n'
                includes+=" -I/usr/include/mkl"
                libraries+=" -lmkl_rt" ;;
            openblas)
                headers+=$'#include <cblas.h>\n'
                if [[ -n "${OPENBLAS_ROOT:-}" ]]; then
                    includes+=" -I$OPENBLAS_ROOT/include"
                    paths+=" -L$OPENBLAS_ROOT/lib -Wl,-rpath,$OPENBLAS_ROOT/lib"
                fi
                libraries+=" -lopenblas" ;;
            gsl)
                headers+=$'#include <gsl/gsl_blas.h>\n#include "gsl-wrappers.h"\n'
                libraries+=" -lgsl -lgslcblas" ;;
            cuda|cublas|cusparse)
                test -f "$cuda/include/cuda_runtime_api.h" || { printf 'Set CUDA_HOME to a CUDA toolkit installation\n' >&2; return 2; }
                if [[ -z "${seen[cuda-flags]:-}" ]]; then
                    headers+=$'#include "cuda-wrappers.h"\n'
                    for prefix in "$cuda" "$cublas" "$cusparse"; do
                        includes+=" -I$prefix/include"
                        paths+=" -L$prefix/lib64 -Wl,-rpath,$prefix/lib64"
                    done
                    libraries+=" -lcublas -lcusparse -lcudart"
                    seen[cuda-flags]=1
                fi ;;
            *) printf 'Unknown library: %s (choose taco, tblis, mkl, openblas, gsl, cuda)\n' "$library" >&2; return 2 ;;
        esac
    done
    export PATH_TO_MOSAIC_ARTIFACT="$root"
    export TENSOR_ALGEBRA_SRC="$root/tensor_algebra_systems_src"
    export TENSOR_ALGEBRA_LIB="$root/tensor_algebra_systems_lib"
    export INCLUDE_HEADERS="$headers" INCLUDE_PATH="$includes" LIB_PATH="$paths"
    export DYNAMIC_LIB_FILES="$libraries -lpthread -lm -ldl"
    export TACO_CFLAGS="${TACO_CFLAGS:--O3 -ffast-math -std=c99}"
    export MKL_THREADING_LAYER=SEQUENTIAL MKL_INTERFACE_LAYER=LP64
    export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}" MKL_NUM_THREADS="${MKL_NUM_THREADS:-1}"
    export TBLIS_NUM_THREADS="${TBLIS_NUM_THREADS:-1}" OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
    export MPLBACKEND=Agg MOSAIC_LIBRARIES="$selection"
}

configure_mosaic_system "${1:-${MOSAIC_SYSTEM:-${MOSAIC_LIBRARIES:-tblis,mkl}}}"
