#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
artifact=${PATH_TO_MOSAIC_ARTIFACT:-$(cd -- "$script_dir/../../.." && pwd)}
backend=${1:-cusparse}
case "$backend" in
    cusparse) target=taco-bench-sddmm-cusparse; option=MOSAIC_CUSPARSE_SDDMM ;;
    cuda_optimized|cuda_row_tiled) target=taco-bench-sddmm-cuda; option=MOSAIC_CUDA_SDDMM ;;
    *) echo "Unknown SDDMM backend: $backend" >&2; exit 2 ;;
esac
benchmark="$artifact/mosaic/build/bin/$target"
if [[ ! -x "$benchmark" ]]; then
    echo "Build $target with -D$option=ON first." >&2
    exit 1
fi

result_dir="$script_dir/result"
mkdir -p -- "$result_dir"
work_dir=$(mktemp -d "$result_dir/.$backend.XXXXXX")
trap 'rm -rf -- "$work_dir"' EXIT

densities=(0.00078125 0.0015625 0.003125 0.00625 0.0125 0.025 0.05 0.1)
for density in "${densities[@]}"; do
    python3 "$artifact/mosaic-benchmarks/data/data_gen.py" \
        --bench sddmm_sp --dim 2000 --nnz "$density" --out_dir "$work_dir"
done

MOSAIC_SDDMM_INPUT_DIR="$work_dir/sddmm_sp" "$benchmark" \
    --benchmark_filter="^bench_sddmm_varySparisty_${backend}/" \
    --benchmark_out_format=json --benchmark_out="$work_dir/results.json"

python3 - "$work_dir/results.json" "${#densities[@]}" "$backend" <<'PY'
import json
import sys

with open(sys.argv[1]) as results:
    runs = json.load(results)["benchmarks"]
errors = [run["error_message"] for run in runs if run.get("error_occurred")]
if errors:
    sys.exit(f"{sys.argv[3]} benchmark failed: " + "; ".join(dict.fromkeys(errors)))
if sum(run.get("aggregate_name") == "median" for run in runs) != int(sys.argv[2]):
    sys.exit(f"{sys.argv[3]} benchmark did not report a median for every density")
PY
mv -f -- "$work_dir/results.json" "$result_dir/$backend"
