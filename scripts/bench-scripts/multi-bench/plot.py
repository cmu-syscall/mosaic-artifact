#!/usr/bin/env python3
"""Draw bound-schedule timing bars for each multi-bench input configuration."""

import argparse
import html
import io
import json
import math
import re
import statistics
import textwrap
import xml.etree.ElementTree as ET
from pathlib import Path

TO_MS = {"ns": 1e-6, "us": 1e-3, "ms": 1.0, "s": 1e3}


def collect_results(document, kernel):
    groups, failures = {}, {}
    dimensions, densities = set(), set()
    pattern = re.compile(r"^bench_multi_" + kernel + r"/schedule:(\d+)(?:/|$)")
    for row in document["benchmarks"]:
        match = pattern.match(row.get("name", ""))
        if not match:
            raise ValueError("Results do not belong to " + kernel)
        index = int(match.group(1))
        group = groups.setdefault(index, {"labels": set(), "samples": [], "medians": []})
        if row.get("label"):
            group["labels"].add(row["label"])
        if row.get("error_occurred"):
            failures.setdefault(index, []).append(row)
            continue
        if row.get("aggregate_name") not in (None, "median"):
            continue
        if "dimension" in row:
            dimensions.add(float(row["dimension"]))
        if "density" in row:
            densities.add(float(row["density"]))
        value = float(row["real_time"]) * TO_MS[row["time_unit"]]
        if not math.isfinite(value) or value < 0:
            raise ValueError("Invalid runtime for schedule " + str(index))
        group["medians" if row.get("aggregate_name") == "median" else "samples"].append(value)
    if not groups:
        raise ValueError("No benchmark results")
    if len(dimensions) > 1 or len(densities) > 1:
        raise ValueError("Do not combine input configurations in one chart")
    bars = []
    for index, group in sorted(groups.items()):
        if index in failures:
            continue
        if len(group["labels"]) != 1 or len(group["medians"]) > 1:
            raise ValueError("Missing/ambiguous schedule label or duplicate median")
        values = group["samples"] or group["medians"]
        bars.append({"index": index, "bound_schedule": next(iter(group["labels"])),
                     "median_ms": statistics.median(values)})
    dimension = next(iter(dimensions), None)
    if dimension is not None and (not math.isfinite(dimension) or not dimension.is_integer()):
        raise ValueError("Invalid dimension counter")
    return bars, failures, int(dimension) if dimension is not None else "unknown", next(iter(densities), None)


def draw_chart(bars, failures, output, dimension, backend="multi"):
    import matplotlib
    matplotlib.use("Agg")
    matplotlib.rcParams.update({"pdf.fonttype": 42, "svg.fonttype": "none"})
    import matplotlib.pyplot as plt

    labels = [textwrap.fill(row["bound_schedule"], width=24,
                            break_long_words=True, break_on_hyphens=False)
              for row in bars]
    label_height = max((label.count("\n") + 1 for label in labels), default=1) * 0.19
    width = max(10, len(bars) * 2.1 + 1.3)
    height = 6.2 + label_height
    fig, ax = plt.subplots(figsize=(width, height))
    fig.subplots_adjust(left=1.0 / width, right=1 - 0.3 / width,
                        bottom=(label_height + 0.7) / height, top=1 - 0.8 / height)
    ax.set_title(f"{backend.upper()} {dimension} x {dimension} | {len(bars)} successful schedules | {len(failures)} failed",
                 loc="left", pad=24)
    ax.set_ylabel("Median execution time (ms)")
    ax.set_xlabel("Bound schedule", labelpad=16)
    ax.spines[["top", "right"]].set_visible(False)
    ax.set_axisbelow(True)
    ax.grid(axis="y", color="#dce3e5", linewidth=0.7)
    ax.tick_params(axis="x", length=0, pad=12)

    if bars:
        times = [row["median_ms"] for row in bars]
        ax.set_ylim(0, max(times) * 1.2 if max(times) > 0 else 1)
        patches = ax.bar(range(len(bars)), times, width=0.65, color="#267d87")
        ax.set_xticks(range(len(bars)))
        ax.set_xticklabels(labels, fontsize=10, fontfamily="monospace")
        ax.set_xlim(-0.65, len(bars) - 0.35)
        for position, (patch, row) in enumerate(zip(patches, bars)):
            patch.set_gid(f"bound-schedule-{row['index']}")
            ax.annotate(f"{row['median_ms']:.6g} ms", (position, row["median_ms"]),
                        xytext=(0, 6), textcoords="offset points", ha="center", fontsize=10)
    else:
        ax.set_xticks([])
        ax.text(0.5, 0.5, "No successful schedules. See failure details in the HTML report.",
                transform=ax.transAxes, ha="center")

    fig.savefig(output / "schedules.pdf")
    svg_buffer = io.StringIO()
    fig.savefig(svg_buffer, format="svg")
    plt.close(fig)

    # SVG titles provide offline browser tooltips without external JavaScript.
    namespace = "http://www.w3.org/2000/svg"
    ET.register_namespace("", namespace)
    root = ET.fromstring(svg_buffer.getvalue())
    elements = {element.get("id"): element for element in root.iter()}
    for row in bars:
        title = ET.Element(f"{{{namespace}}}title")
        title.text = f"{row['bound_schedule']}\nMedian: {row['median_ms']:.12g} ms"
        elements[f"bound-schedule-{row['index']}"].insert(0, title)
    root.set("role", "img")
    root.set("aria-label", f"Bound schedules and their median execution times at dimension {dimension}")
    return ET.tostring(root, encoding="unicode")


def write_html(svg, bars, failures, output, dimension, backend="multi"):
    failures_html = ""
    if failures:
        items = []
        for index, rows in sorted(failures.items()):
            label = rows[0].get("label") or rows[0]["name"]
            messages = "; ".join(sorted({row.get("error_message", "Benchmark failed") for row in rows}))
            items.append(f"<li><pre>{html.escape(label)}</pre>{html.escape(messages)}</li>")
        failures_html = '<section class="failures"><h2>Failed schedules (not plotted)</h2><ul>' + "".join(items) + "</ul></section>"
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Bound schedule performance - {dimension}</title>
<style>
body {{ margin: 0; padding: 24px; color: #202a30; background: #f5f7f8; font: 15px Arial, sans-serif; }}
h1 {{ font-size: 24px; margin: 0 0 10px; }}
p {{ margin: 0 0 20px; }}
.chart {{ overflow-x: auto; background: white; border: 1px solid #dce3e5; }}
.chart svg {{ display: block; max-width: none; }}
.failures {{ margin-top: 24px; color: #9b302a; }}
pre {{ white-space: pre-wrap; overflow-wrap: anywhere; }}
</style></head><body>
<h1>Bound schedule performance</h1>
<p>{backend.upper()} {dimension} x {dimension} | Median wall-clock time | {len(bars)} successful schedules | {len(failures)} failed</p>
<div class="chart" tabindex="0" aria-label="Scrollable bound schedule bar chart">{svg}</div>
{failures_html}
</body></html>"""
    (output / "schedules.html").write_text(page, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kernel", choices=("gemm", "spmm", "sddmm"), required=True)
    parser.add_argument("--run", type=Path, required=True)
    args = parser.parse_args()
    if not args.run.is_dir():
        parser.error("--run must be an existing result directory")
    paths = ([args.run / "results.json"] if (args.run / "results.json").is_file()
             else sorted(args.run.glob("*/results.json")))
    if not paths:
        parser.error("No results.json files found")
    errors = []
    for path in paths:
        try:
            bars, failures, dimension, density = collect_results(json.loads(path.read_text()), args.kernel)
            output = path.parent / "plots"
            output.mkdir(exist_ok=True)
            status = path.parent / "status.txt"
            partial = status.exists() and status.read_text().strip() != "passed"
            display = args.kernel + (f" | density {density:g}" if density is not None else "")
            if partial:
                display += " | INCOMPLETE/FAILED RUN"
            svg = draw_chart(bars, failures, output, dimension, display)
            write_html(svg, bars, failures, output, dimension, display)
            (output / "manifest.json").write_text(json.dumps({
                "source": str(path.resolve()), "kernel": args.kernel, "dimension": dimension,
                "density": density, "statistic": "median real_time", "time_unit": "ms",
                "partial_run": partial, "bars": bars, "failures": failures,
            }, indent=2, allow_nan=False) + "\n")
            print(f"Created {output}/schedules.pdf and schedules.html")
            if failures or partial:
                print("WARNING: failed schedules are excluded; this is not a complete successful comparison.")
        except (ValueError, KeyError, OSError) as error:
            errors.append(f"{path}: {error}")
    if errors:
        raise SystemExit("\n".join(errors))


if __name__ == "__main__":
    main()
