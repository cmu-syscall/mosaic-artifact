"""Draw grouped median runtimes from one or more SuiteSparse benchmark CSVs."""

import argparse
import csv
import math
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.ticker import StrMethodFormatter


LABELS = {
    "taco": "TACO", "taco_scheduled": "TACO scheduled",
    "optimized": "Optimized CPU", "cpu_blocked": "Blocked CPU",
    "blas": "OpenBLAS", "mkl": "MKL GEMM", "dot_mkl": "MKL dot",
    "gemv_mkl": "MKL GEMV", "gemv_gsl": "GSL GEMV", "tblis": "TBLIS",
    "cusparse": "cuSPARSE", "cuda_optimized": "Optimized CUDA",
    "cuda_row_tiled": "Row-tiled CUDA", "sampled_gsl": "GSL sampled dot",
    "mosaic_sampled_gsl": "Mosaic GSL sampled dot",
    "bsmr": "BSMR-SDDMM",
}
COLORS = [
    "#466a9e", "#89a5ca", "#337b69", "#81bba8", "#bc6c25", "#843c64",
    "#bf74a0", "#e3a7c7", "#a78b39", "#7d828a", "#003f76", "#197eaf",
    "#5fc4e4", "#da432d", "#792e21", "#30273d",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    data = {}
    for path in args.inputs:
        with path.open(newline="") as stream:
            for row in csv.DictReader(stream):
                matrix, backend = row["matrix"], row["backend"]
                if row["error"]:
                    parser.error(f"{path}: {matrix}/{backend}: {row['error']}")
                time = float(row["median_us"])
                if not math.isfinite(time) or time <= 0:
                    parser.error(f"{path}: invalid runtime for {matrix}/{backend}")
                results = data.setdefault(matrix, {})
                if backend in results:
                    parser.error(f"{path}: duplicate result for {matrix}/{backend}")
                results[backend] = time

    backends = set().union(*(results.keys() for results in data.values()))
    if not data or any(results.keys() != backends for results in data.values()):
        parser.error("Every matrix must have a timing for every plotted backend")
    order = sorted(backends, key=lambda backend: list(LABELS).index(backend)
                   if backend in LABELS else len(LABELS))
    values = [time for results in data.values() for time in results.values()]
    floor = 10 ** math.floor(math.log10(min(values) * 0.8))

    fig, ax = plt.subplots(figsize=(15, 6.4))
    fig.subplots_adjust(left=.075, right=.985, top=.88, bottom=.255)
    centers = np.arange(len(data))
    width = .86 / len(order)
    for index, backend in enumerate(order):
        times = np.array([results[backend] for results in data.values()])
        offset = (index - (len(order) - 1) / 2) * width
        ax.bar(centers + offset, times - floor, width, bottom=floor,
               color=COLORS[index % len(COLORS)], edgecolor="white", linewidth=.32,
               label=LABELS.get(backend, backend))
    for boundary in centers[:-1] + .5:
        ax.axvline(boundary, color="#c9d0d7", linewidth=.8, zorder=0)
    ax.set_yscale("log")
    ax.set_ylim(floor, max(values) * 1.45)
    ax.set_xlim(-.5, len(data) - .5)
    ax.set_xticks(centers, list(data))
    ax.set_ylabel("Median runtime (µs, log scale)")
    ax.yaxis.set_major_formatter(StrMethodFormatter("{x:,.0f}"))
    ax.set_title("SDDMM Performance on Mosaic Paper Matrices",
                 loc="left", fontweight="bold", pad=14)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce2e8")
    ax.spines[["top", "right"]].set_visible(False)
    ax.legend(loc="upper center", bbox_to_anchor=(.5, -.10), ncol=5, frameon=False)
    fig.savefig(args.output)
    plt.close(fig)


if __name__ == "__main__":
    main()
