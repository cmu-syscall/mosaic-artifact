#!/usr/bin/env bash
set -euo pipefail

root="${PATH_TO_MOSAIC_ARTIFACT:-/mosaic-artifact}"
out="${1:?Usage: bash scripts/docker-smoke.sh /results/new-directory}"
mkdir -p "$(dirname "$out")"
mkdir "$out"
out="$(cd "$out" && pwd)"
cd "$root/scripts/bench-scripts"

for libraries in taco tblis,mkl gsl openblas; do
    source "$root/scripts/mosaic_env_var.sh" "$libraries"
    interfaces="$libraries"
    [[ "$libraries" == taco ]] || interfaces="${libraries//,/.*,}.*"
    for kernel in gemm spmm sddmm ttv blockspmm spadd; do
        directory="$out/$libraries-$kernel"
        make "run-multi-$kernel" INPUT=synthetic DIMS=3 DENSITIES=0.25 \
            INTERFACES="$interfaces" REPETITIONS=2 CONSTANT_FOLDING=true WARMUP=0 OUT="$directory"
        make "draw-multi-$kernel" OUT="$directory"
    done
done

source "$root/scripts/mosaic_env_var.sh" tblis,mkl
for kernel in gemm spmm sddmm; do
    directory="$out/matrix-market-$kernel"
    make "run-multi-$kernel" INPUT=matrix-market MATRIX="$root/mosaic/test/data/ds33.mtx" \
        INTERFACES='tblis.*,mkl.*' REPETITIONS=2 CONSTANT_FOLDING=true WARMUP=0 OUT="$directory"
    make "draw-multi-$kernel" OUT="$directory"
done

source "$root/scripts/mosaic_env_var.sh" taco
make run-multi-gemm DIMS=3,8 DENSITIES=0.25,1 INTERFACES=taco \
    REPETITIONS=2 CONSTANT_FOLDING=false WARMUP=0 OUT="$out/sweep-no-folding"
make draw-multi-gemm OUT="$out/sweep-no-folding"

mkdir "$out/legacy"
for backend in taco tblis mkl gsl blas; do
    library="$backend"
    [[ "$backend" != blas ]] || library=openblas
    source "$root/scripts/mosaic_env_var.sh" "$library"
    "$root/mosaic/build/bin/taco-bench" --benchmark_filter="^bench_gemv_${backend}/250/" \
        --benchmark_out_format=json --benchmark_out="$out/legacy/$backend.json" \
        > "$out/legacy/$backend.log" 2>&1
done

source "$root/scripts/mosaic_env_var.sh" taco
"$root/mosaic/build/bin/taco-test" --gtest_filter='scheduleConstants.*:acceleratorMatches.*:preciseTensorMatching.*:LibraryMatchCandidates.*:scheduleLowering.*:interfaceArguments.*' \
    > "$out/compiler-tests.txt" 2>&1

python3 - "$out" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
results = sorted(root.glob('*/*/results.json'))
assert len(results) == 31, f'Expected 31 configurations, found {len(results)}'
samples = 0
for path in results:
    rows = json.loads(path.read_text())['benchmarks']
    assert rows and not any(row.get('error_occurred') for row in rows), path
    timings = [row for row in rows if row.get('run_type') == 'iteration']
    assert timings, path
    samples += len(timings)
    directory = path.parent
    assert list((directory / 'code').glob('schedule*.c')), directory
    assert (directory / 'plots/schedules.pdf').stat().st_size > 0, directory
    assert (directory / 'plots/schedules.html').stat().st_size > 0, directory

for name, symbol in [('tblis,mkl-gemm', 'tblis_tensor_mult'),
                     ('tblis,mkl-gemm', 'sgemm'), ('gsl-gemm', 'gsl_blas_sgemm'),
                     ('openblas-gemm', 'cblas_sgemm')]:
    rows = json.loads((root / name / '0/results.json').read_text())['benchmarks']
    assert any(symbol in row.get('label', '') for row in rows), (name, symbol)
for backend in ['taco', 'tblis', 'mkl', 'gsl', 'blas']:
    rows = json.loads((root / 'legacy' / f'{backend}.json').read_text())['benchmarks']
    assert rows and not any(row.get('error_occurred') for row in rows), backend
    assert any(row.get('aggregate_name') == 'median' and 'real_time' in row for row in rows), backend
print(f'Passed: {len(results)} configurations, {samples} individual timing samples, C files and plots.')
print('Also passed: five original GEMV benchmarks at dimension 250.')
print('Workflow validation only; benchmark timings do not establish numerical correctness.')
PY
