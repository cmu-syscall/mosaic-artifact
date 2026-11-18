#!/usr/bin/env bash
#SBATCH --job-name=mosaic-multi
#SBATCH --partition=ghx4
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --gpus-per-node=1
#SBATCH --mem=32G
#SBATCH --time=00:45:00

set -euo pipefail
root="${SLURM_SUBMIT_DIR:?Submit from the artifact root}"
module load cudatoolkit/25.5_12.9 openblas/0.3.27 cmake/3.30.2
export CC=gcc CXX=g++
export CUDA_HOME=/opt/nvidia/hpc_sdk/Linux_aarch64/25.5/cuda/12.9
export CUBLAS_ROOT=/opt/nvidia/hpc_sdk/Linux_aarch64/25.5/math_libs/12.9
export CUSPARSE_ROOT="$CUBLAS_ROOT"
export OPENBLAS_ROOT="$OPENBLAS_HOME"
export PATH_TO_MOSAIC_ARTIFACT="$root"
source "$root/scripts/mosaic_env_var.sh" "${MOSAIC_LIBRARIES:-cuda,openblas}"
kernel="${1:-gemm}"
case "$kernel" in gemm|spmm|sddmm) ;; *) echo "Expected gemm, spmm or sddmm" >&2; exit 2 ;; esac
cmake -S "$root/mosaic" -B "$root/mosaic/build" -DCMAKE_BUILD_TYPE=Release \
  -DGIT_SUBMODULE=OFF -DBENCHMARK_ENABLE_TESTING=OFF -DBENCHMARK_DOWNLOAD_DEPENDENCIES=OFF
cmake --build "$root/mosaic/build" --parallel "$SLURM_CPUS_PER_TASK" --target "taco-multi-$kernel"
out="${OUT:-$root/local-tests/$kernel-delta-$SLURM_JOB_ID}"
srun make -C "$root/scripts/bench-scripts" "run-multi-$kernel" \
  DIMS="${DIMS:-500}" DENSITIES="${DENSITIES:-0.1}" \
  INTERFACES="${INTERFACES:-cuda.*,openblas.*}" REPETITIONS="${REPETITIONS:-3}" \
  CONSTANT_FOLDING="${CONSTANT_FOLDING:-true}" WARMUP="${WARMUP:-0}" OUT="$out"
