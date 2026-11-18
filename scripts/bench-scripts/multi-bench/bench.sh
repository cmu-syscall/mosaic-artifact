#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
kernel="${1:?Expected a multi-benchmark kernel}"
case "$kernel" in gemm|spmm|sddmm|ttv|blockspmm|spadd) ;; *) echo "Unknown kernel: $kernel" >&2; exit 1 ;; esac
input="${INPUT:-synthetic}"
case "$kernel:$input" in
  ttv:matrix-market|blockspmm:matrix-market|spadd:matrix-market)
    echo "$kernel currently supports INPUT=synthetic only" >&2
    exit 1 ;;
esac
matrix="${MATRIX:-}"
target="taco-multi-$kernel"
if [[ "$input" == matrix-market ]]; then target="taco-multi-suitesparse-$kernel"; fi
binary="${MULTI_BENCH_BIN:-$root/mosaic/build/bin/$target}"
[[ -x "$binary" ]] || { echo "Build $target first" >&2; exit 1; }
binary="$(cd "$(dirname "$binary")" && pwd)/$(basename "$binary")"
if [[ "${2:-}" == --list-interfaces ]]; then
  exec "$binary" --list-interfaces
fi
export CACHE_KERNELS=0
if [[ "$input" == matrix-market ]]; then
  [[ -f "$matrix" ]] || { echo "MATRIX must name an existing file" >&2; exit 1; }
  [[ "${DIMS:-250}" == 250 && "${DENSITIES:-1}" == 1 ]] || { echo "Omit DIMS and DENSITIES for real input" >&2; exit 1; }
  matrix="$(cd "$(dirname "$matrix")" && pwd)/$(basename "$matrix")"
elif [[ "$input" != synthetic || -n "$matrix" ]]; then
  echo "Use INPUT=synthetic or INPUT=matrix-market MATRIX=/path/file.mtx" >&2
  exit 1
fi
output="${OUT:-$root/local-tests/$kernel-multi-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$(dirname "$output")"
mkdir "$output"
output="$(cd "$output" && pwd)"
IFS=, read -r -a dims <<< "${DIMS:-250}"
IFS=, read -r -a densities <<< "${DENSITIES:-1}"
failed=0
case_index=0
for dim in "${dims[@]}"; do
  for density in "${densities[@]}"; do
    directory="$output/$case_index"
    mkdir "$directory"
    mkdir "$directory/code"
    args=("--interfaces=${INTERFACES:-${BACKENDS:-taco}}" "--constant-folding=${CONSTANT_FOLDING:-true}")
    if [[ "$input" == matrix-market ]]; then
      args+=("--matrix=$matrix")
      echo "Running $kernel: matrix $matrix -> $directory"
    else
      args+=("--dim=$dim" "--density=$density")
      echo "Running $kernel: dimension $dim, density $density -> $directory"
    fi
    if ! (cd "$directory" && "$binary" "${args[@]}" --benchmark_filter="${FILTER:-.*}" --benchmark_repetitions="${REPETITIONS:-10}" --benchmark_min_warmup_time="${WARMUP:-0}" --benchmark_out_format=json --benchmark_out="$directory/results.json" > "$directory/errors.log" 2>&1); then
      echo "Failed: $directory (see errors.log and results.json if produced)" >&2
      failed=1
    else
      rm "$directory/errors.log"
    fi
    case_index=$((case_index + 1))
  done
done
echo "Results: $output"
exit "$failed"
