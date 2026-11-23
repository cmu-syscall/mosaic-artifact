"""Run the checked-in SuiteSparse lists and emit one CSV row per matrix and backend."""

import argparse
import csv
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from urllib.parse import quote
from urllib.request import urlopen

import numpy as np
from scipy import io, sparse


ARTIFACT = Path(__file__).resolve().parents[3]
DATA = ARTIFACT / "mosaic-benchmarks/data"
SITE = "https://sparse.tamu.edu"
TARGETS = {
    "taco": "taco-bench",
    "taco_scheduled": "taco-bench",
    "optimized": "taco-bench",
    "cpu_blocked": "taco-bench",
    "blas": "taco-bench",
    "mkl": "taco-bench-suitesparse-mkl",
    "dot_mkl": "taco-bench-suitesparse-mkl",
    "gemv_mkl": "taco-bench-suitesparse-mkl",
    "mosaic_sampled_gsl": "taco-bench",
    "sampled_gsl": "taco-bench",
    "gemv_gsl": "taco-bench",
    "tblis": "taco-bench",
    "cusparse": "taco-bench-sddmm-cusparse",
    "cuda_optimized": "taco-bench-sddmm-cuda",
    "cuda_row_tiled": "taco-bench-sddmm-cuda",
    "bsmr": "taco-bench-suitesparse-bsmr",
}


def index_groups(cache):
    index = cache / "ssstats.csv"
    if not index.exists():
        with urlopen(f"{SITE}/files/ssstats.csv", timeout=60) as response:
            contents = response.read().decode("utf-8-sig")
        with tempfile.TemporaryDirectory(dir=cache) as scratch:
            pending = Path(scratch) / index.name
            pending.write_text(contents)
            pending.replace(index)
    groups = {}
    with index.open(newline="") as source:
        for row in csv.reader(source):
            if len(row) >= 5 and all(value.isdigit() for value in row[2:5]):
                groups.setdefault(row[1], []).append(row[0])
    if not groups:
        raise ValueError(f"No matrix entries in {index}")
    return groups


def matrix_file(cache, name, groups, download):
    for path in (cache / name / f"{name}.mtx", cache / f"{name}.mtx"):
        if path.is_file():
            return path
    if not download:
        raise FileNotFoundError(f"{name}.mtx is missing from {cache}")

    candidates = groups().get(name, [])
    if len(candidates) != 1:
        raise ValueError(f"Expected one SuiteSparse group for {name}, found {candidates}")
    group = quote(candidates[0], safe="")
    url = f"{SITE}/MM/{group}/{quote(name, safe='')}.tar.gz"
    path = cache / f"{name}.mtx"
    with tempfile.TemporaryDirectory(dir=cache) as scratch:
        archive = Path(scratch) / "matrix.tar.gz"
        with urlopen(url, timeout=60) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        pending = Path(scratch) / path.name
        with tarfile.open(archive) as package:
            member = package.getmember(f"{name}/{name}.mtx")
            if not member.isfile():
                raise ValueError(f"Expected a regular Matrix Market file in {url}")
            with package.extractfile(member) as source, pending.open("wb") as output:
                shutil.copyfileobj(source, output)
        pending.replace(path)
    return path


def prepare_mask(source, target):
    matrix = io.mmread(source)
    if not sparse.issparse(matrix):
        matrix = sparse.coo_matrix(matrix)
    matrix = matrix.tocoo()
    matrix.eliminate_zeros()
    matrix.data = np.ones(matrix.nnz, dtype=np.float32)
    mask = matrix.tocsr()
    mask.data.fill(1)
    if not mask.nnz or max(*mask.shape, mask.nnz) >= 2**31:
        raise ValueError("Expected a nonempty matrix with dimensions and stored entries fitting in int32")
    io.mmwrite(target, mask, field="real", symmetry="general")
    return dict(rows=mask.shape[0], columns=mask.shape[1], nnz=mask.nnz, inner=100)


def benchmark_env(mask):
    return {**os.environ, "PATH_TO_MOSAIC_ARTIFACT": str(ARTIFACT),
            "INCLUDE_PATH": " ", "LIB_PATH": " ", "INCLUDE_HEADERS": "", "DYNAMIC_LIB_FILES": "",
            "MOSAIC_SUITESPARSE_MASK": str(mask)}


def run_backend(binary, backend, mask, directory):
    output = directory / f"{backend}.json"
    env = benchmark_env(mask)
    if backend == "mosaic_sampled_gsl":
        env.update(INCLUDE_PATH=f" -I{ARTIFACT}/mosaic/include -I{ARTIFACT}/tensor_algebra_systems_lib",
                   INCLUDE_HEADERS='#include "sddmm-gsl.h"', DYNAMIC_LIB_FILES="-lgsl -lgslcblas")
    completed = subprocess.run(
        [str(binary), f"--benchmark_filter=^bench_suitesparse_sddmm_{backend}(/|$)",
         f"--benchmark_out={output}", "--benchmark_out_format=json"],
        env=env,
        capture_output=True, text=True, check=False,
    )
    if completed.returncode:
        raise ValueError(completed.stderr.strip() or f"Benchmark exited with {completed.returncode}")
    runs = json.loads(output.read_text())["benchmarks"]
    for run in runs:
        if run.get("error_occurred"):
            raise ValueError(run["error_message"])
    medians = [run for run in runs if run.get("aggregate_name") == "median"]
    if len(medians) != 1 or medians[0].get("time_unit") != "us":
        raise ValueError(f"Expected one median in microseconds from {binary.name}. Rebuild the target.")
    return medians[0]["real_time"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="append", type=Path, help="Matrix list file, repeatable")
    parser.add_argument("--limit", type=int, help="Use only the first N matrices of each list")
    parser.add_argument("--matrix-dir", type=Path, default=DATA / "suitesparse")
    parser.add_argument("--bin-dir", type=Path, default=ARTIFACT / "mosaic/build/bin")
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("result") / "timings.csv")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--backend", choices=TARGETS, action="append", help="Defaults to all built backends")
    selection.add_argument("--require-all-backends", action="store_true",
                           help="Fail before timing if any backend is unavailable")
    parser.add_argument("--offline", action="store_true", help="Use only cached Matrix Market files")
    args = parser.parse_args()
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be positive")
    lists = args.list or sorted((DATA / "tensor_names").glob("suitesparse*.txt"))
    if args.backend:
        backends = list(dict.fromkeys(args.backend))
    else:
        available = set()
        for name in dict.fromkeys(TARGETS.values()):
            binary = args.bin_dir / name
            if not os.access(binary, os.X_OK):
                continue
            listed = subprocess.run(
                [str(binary.resolve()), "--benchmark_list_tests", "--benchmark_filter=^bench_suitesparse_sddmm_"],
                env=benchmark_env("list-only"),
                capture_output=True, text=True,
            )
            if listed.returncode:
                parser.error(f"Could not list benchmarks in {binary}: {listed.stderr.strip()}")
            available.update(line.split("/", 1)[0] for line in listed.stdout.splitlines())
        backends = [backend for backend in TARGETS if f"bench_suitesparse_sddmm_{backend}" in available]
        if args.require_all_backends:
            missing = [backend for backend in TARGETS if backend not in backends]
            if missing:
                parser.error(f"Rebuild the benchmark executables. Missing backends: {', '.join(missing)}")
    if not backends:
        parser.error("Build at least one SDDMM benchmark executable first")
    for backend in backends:
        if not os.access(args.bin_dir / TARGETS[backend], os.X_OK):
            parser.error(f"Build {TARGETS[backend]} first")
    print("Backends:", ", ".join(backends), flush=True)

    matrices = {}
    for path in lists:
        names = dict.fromkeys(line.strip() for line in path.read_text().splitlines() if line.strip())
        for position, name in enumerate(list(names)[:args.limit], start=1):
            if not re.fullmatch(r"[A-Za-z0-9_.+-]+", name) or name in (".", ".."):
                parser.error(f"Invalid matrix name {name!r} in {path}")
            matrices.setdefault(name, []).append((path.stem, position))
    if not matrices:
        parser.error("No matrices selected")
    args.matrix_dir.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    groups_by_name = None
    index_error = None

    def groups():
        nonlocal groups_by_name, index_error
        if groups_by_name is None and index_error is None:
            try:
                groups_by_name = index_groups(args.matrix_dir)
            except (OSError, ValueError) as error:
                index_error = error
        if index_error is not None:
            raise index_error
        return groups_by_name

    failures = 0
    fields = ["list", "position", "matrix", "backend", "rows", "columns", "nnz",
              "inner", "median_us", "error"]
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for name, memberships in matrices.items():
            print(name, flush=True)
            with tempfile.TemporaryDirectory() as scratch:
                directory = Path(scratch)
                mask = directory / "mask.mtx"
                metadata = {}
                setup_error = ""
                try:
                    source = matrix_file(args.matrix_dir, name, groups, not args.offline)
                    metadata = prepare_mask(source, mask)
                except (OSError, ValueError, tarfile.TarError, KeyError) as error:
                    setup_error = str(error)
                for backend in backends:
                    median, error = "", setup_error
                    if not error:
                        try:
                            median = run_backend((args.bin_dir / TARGETS[backend]).resolve(),
                                                 backend, mask, directory)
                        except (OSError, ValueError, KeyError) as failure:
                            error = str(failure)
                    if error:
                        failures += 1
                        print(f"  {backend}: {error}", file=sys.stderr)
                    for list_name, position in memberships:
                        writer.writerow(dict(list=list_name, position=position, matrix=name,
                                             backend=backend, median_us=median, error=error, **metadata))
            stream.flush()
    print(f"Wrote {args.output} with {failures} failed matrix/backend runs")
    return int(failures > 0)


if __name__ == "__main__":
    sys.exit(main())
