
#!/usr/bin/env python3

"""
Compare ALF Figure of Merit (FOM) across different node counts.

Outputs:
    FOM_results.txt (inside each ALF directory)
    FOM_comparison.csv
    FOM_vs_nodes.png
    FOM_scaling_efficiency.png
    MD_time_vs_nodes.png
    QM_time_vs_nodes.png
    ML_time_vs_nodes.png
    MD_time_vs_configs.png
    QM_time_vs_configs.png
    ML_time_vs_configs.png
    Stage_percent_vs_nodes.png
    Stage_percent_vs_configs.png
"""

import argparse
import csv
import math
import re
import subprocess
import sys
from pathlib import Path

import matplotlib.pyplot as plt


def parse_duration(value):
    """Convert HH:MM:SS.ss to seconds."""
    hours, minutes, seconds = value.strip().split(":")
    return (
        int(hours) * 3600
        + int(minutes) * 60
        + float(seconds)
    )


def set_sparse_xticks(ax, values, max_ticks=6):
    """Display a subset of actual x values to avoid overlapping labels."""
    values = sorted(set(values))

    if not values:
        return

    if len(values) <= max_ticks:
        ticks = values
    else:
        indices = [
            round(i * (len(values) - 1) / (max_ticks - 1))
            for i in range(max_ticks)
        ]
        ticks = [values[i] for i in sorted(set(indices))]

    ax.set_xticks(ticks)


def extract_results(output):
    """Extract FOM, configuration counts, and extrapolated stage times."""

    fom_patterns = [
        r"FOM\s*\(components/hour\)\s*:\s*([\d,]+(?:\.\d+)?)",
        r"FOM\s*\(comp/hour\)\s*:\s*([\d,]+(?:\.\d+)?)",
    ]

    fom = None

    for pattern in fom_patterns:
        match = re.search(pattern, output, re.IGNORECASE)
        if match:
            fom = float(match.group(1).replace(",", ""))
            break

    if fom is None:
        raise ValueError("Could not extract FOM from analyzer output.")

    section = re.search(
        r"Stage Durations:\s*(.*?)(?:\n\s*Figure of Merit|\n\s*Time Distribution:|\Z)",
        output,
        re.DOTALL | re.IGNORECASE,
    )

    if section is None:
        raise ValueError("Could not find Stage Durations section.")

    stage_text = section.group(1)

    patterns = {
        "md_time": r"MD Sampling\s*:\s*(\d+:\d+:[\d.]+)",
        "qm_time": r"QM Labeling\s*:\s*(\d+:\d+:[\d.]+)",
        "ml_time": r"ML Training\s*:\s*(\d+:\d+:[\d.]+)",
        "total_time": r"Total\s*:\s*(\d+:\d+:[\d.]+)",
    }

    results = {"fom": fom}

    for key, pattern in patterns.items():
        match = re.search(pattern, stage_text)

        if match is None:
            raise ValueError(f"Could not extract {key}.")

        results[key] = parse_duration(match.group(1))

    # Extract configuration counts
    count_patterns = {
        "md_trajectories": (
            r"Trajectories analyzed\s*:\s*([\d,]+)"
        ),
        "qm_calcs": (
            r"Extrapolated QM calcs\s*:\s*([\d,]+)"
        ),
    }

    for key, pattern in count_patterns.items():
        match = re.search(pattern, output, re.IGNORECASE)

        if match is None:
            raise ValueError(f"Could not extract {key}.")

        results[key] = int(match.group(1).replace(",", ""))

    return results


def find_alf_directory(base_path, nodes):
    """
    Find an ALF directory matching nodes_NMD_*.

    Example:
        nodes_4MD_64QM_1ML
        nodes_8MD_64QM_1ML
    """
    pattern = f"nodes_{nodes}MD_*"

    matches = sorted(
        path for path in base_path.glob(pattern)
        if path.is_dir()
    )

    if not matches:
        raise FileNotFoundError(
            f"No directory matching {pattern}"
        )

    if len(matches) > 1:
        raise ValueError(
            f"Multiple directories match {pattern}: "
            + ", ".join(str(p) for p in matches)
        )

    return matches[0]


def run_analysis(
    analyzer,
    alf_dir,
    timestep,
    md_duration,
    epochs,
):
    """Run analyze_FOM.py and save its unmodified output."""

    command = [
        sys.executable,
        str(analyzer),
        "--alf_path",
        str(alf_dir),
        "--timestep",
        str(timestep),
        "--md-duration",
        str(md_duration),
        "--epochs",
        str(epochs),
    ]

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )

    output_file = alf_dir / "FOM_results.txt"

    with output_file.open("w") as f:
        f.write(result.stdout)

        if result.returncode != 0:
            f.write("\nAnalysis failed:\n")
            f.write(result.stderr)

    if result.returncode != 0:
        raise RuntimeError(
            f"Analyzer failed for {alf_dir}: "
            f"{result.stderr.strip()}"
        )

    return extract_results(result.stdout)


def calculate_scaling(results):
    """Calculate ideal FOM scaling and stage time percentages."""

    results.sort(key=lambda item: item["nodes"])

    baseline = results[0]

    baseline_nodes = baseline["nodes"]
    baseline_fom = baseline["fom"]

    for result in results:
        nodes = result["nodes"]

        ideal_fom = (
            baseline_fom * nodes / baseline_nodes
        )

        efficiency = (
            100.0 * result["fom"] / ideal_fom
            if ideal_fom > 0 else 0.0
        )

        result["ideal_fom"] = ideal_fom
        result["efficiency_percent"] = efficiency

        total = result["total_time"]

        for stage in ("md", "qm", "ml"):
            stage_time = result[f"{stage}_time"]

            result[f"{stage}_time_hours"] = (
                stage_time / 3600.0
            )

            result[f"{stage}_percent"] = (
                100.0 * stage_time / total
                if total > 0 else 0.0
            )

        result["total_time_hours"] = total / 3600.0


def save_csv(results, output_file):
    """Save comparison results with controlled numeric precision."""

    columns = [
        "nodes",
        "directory",
        "md_trajectories",
        "qm_calcs",
        "fom",
        "ideal_fom",
        "efficiency_percent",
        "md_time_hours",
        "qm_time_hours",
        "ml_time_hours",
        "total_time_hours",
        "md_percent",
        "qm_percent",
        "ml_percent",
    ]

    with output_file.open("w", newline="") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=columns,
        )

        writer.writeheader()

        for result in results:
            row = {
                "nodes": result["nodes"],
                "directory": result["directory"],

                "md_trajectories": result["md_trajectories"],
                "qm_calcs": result["qm_calcs"],

                # FOM: no decimal places
                "fom": f'{result["fom"]:.0f}',
                "ideal_fom": f'{result["ideal_fom"]:.0f}',

                # Percentages: 5 significant figures
                "efficiency_percent":
                    f'{result["efficiency_percent"]:.5g}',

                "md_percent":
                    f'{result["md_percent"]:.5g}',
                "qm_percent":
                    f'{result["qm_percent"]:.5g}',
                "ml_percent":
                    f'{result["ml_percent"]:.5g}',

                # Hours: 3 significant figures
                "md_time_hours":
                    f'{result["md_time_hours"]:.3g}',
                "qm_time_hours":
                    f'{result["qm_time_hours"]:.3g}',
                "ml_time_hours":
                    f'{result["ml_time_hours"]:.3g}',
                "total_time_hours":
                    f'{result["total_time_hours"]:.3g}',
            }

            writer.writerow(row)


def plot_fom(results, output_file):
    """Plot measured FOM and ideal linear scaling."""

    nodes = [r["nodes"] for r in results]
    fom = [r["fom"] for r in results]
    ideal = [r["ideal_fom"] for r in results]

    fig, ax = plt.subplots(figsize=(8, 5))

    ax.plot(
        nodes,
        fom,
        "o-",
        linewidth=2,
        markersize=7,
        label="Measured FOM",
    )

    ax.plot(
        nodes,
        ideal,
        "--",
        linewidth=2,
        label="Ideal Linear Scaling",
    )

    ax.set_xlabel("Number of Nodes")
    ax.set_ylabel("Force Components Learned per Hour")
    ax.set_title("ALF Figure of Merit Scaling")

    ax.set_ylim(bottom=0)
    set_sparse_xticks(ax, nodes, max_ticks=6)

    ax.grid(True, alpha=0.3)
    ax.legend()

    fig.tight_layout()
    fig.savefig(output_file, dpi=300)
    plt.close(fig)


def plot_efficiency(results, output_file):
    """Plot overall FOM scaling efficiency."""

    nodes = [r["nodes"] for r in results]
    efficiency = [
        r["efficiency_percent"] for r in results
    ]

    fig, ax = plt.subplots(figsize=(8, 5))

    ax.plot(
        nodes,
        efficiency,
        "o-",
        linewidth=2,
        markersize=7,
        label="Measured Efficiency",
    )

    ax.axhline(
        100,
        linestyle="--",
        linewidth=2,
        color="gray",
        label="Ideal Linear Scaling (100%)",
    )

    ax.set_xlabel("Number of Nodes")
    ax.set_ylabel("Scaling Efficiency (%)")
    ax.set_title("ALF FOM Scaling Efficiency")

    ax.set_ylim(bottom=0)
    set_sparse_xticks(ax, nodes, max_ticks=6)

    ax.grid(True, alpha=0.3)
    ax.legend()

    fig.tight_layout()
    fig.savefig(output_file, dpi=300)
    plt.close(fig)


def plot_stage_time(results, stage, output_file):
    """Plot extrapolated stage time versus number of nodes."""

    labels = {
        "md": "MD Sampling",
        "qm": "QM Labeling",
        "ml": "ML Training",
    }

    nodes = [r["nodes"] for r in results]

    times = [
        r[f"{stage}_time_hours"]
        for r in results
    ]

    fig, ax = plt.subplots(figsize=(8, 5))

    ax.plot(
        nodes,
        times,
        "o-",
        linewidth=2,
        markersize=7,
        label=labels[stage],
    )

    ax.set_xlabel("Number of Nodes")
    ax.set_ylabel("Extrapolated Time (hours)")
    ax.set_title(f"{labels[stage]} Execution Time")

    ax.set_ylim(bottom=0)
    set_sparse_xticks(ax, nodes, max_ticks=6)

    ax.grid(True, alpha=0.3)
    ax.legend()

    fig.tight_layout()
    fig.savefig(output_file, dpi=300)
    plt.close(fig)


def plot_stage_configs(results, stage, output_file):
    """Plot extrapolated stage time versus number of configurations."""

    labels = {
        "md": "MD Sampling",
        "qm": "QM Labeling",
        "ml": "ML Training",
    }

    data = sorted(
        (
            r["qm_calcs"],
            r[f"{stage}_time_hours"],
        )
        for r in results
    )

    configs = [item[0] for item in data]
    times = [item[1] for item in data]

    fig, ax = plt.subplots(figsize=(8, 5))

    ax.plot(
        configs,
        times,
        "o-",
        linewidth=2,
        markersize=7,
        label=labels[stage],
    )

    ax.set_xlabel("Number of Configurations")
    ax.set_ylabel("Extrapolated Time (hours)")
    ax.set_title(f"{labels[stage]} Execution Time")

    ax.set_ylim(bottom=0)
    set_sparse_xticks(ax, configs, max_ticks=6)

    ax.grid(True, alpha=0.3)
    ax.legend()

    fig.tight_layout()
    fig.savefig(output_file, dpi=300)
    plt.close(fig)


def plot_stage_percent(results, x_type, output_file):
    """Plot MD, QM, and ML contributions to total execution time."""

    if x_type == "nodes":
        x_values = [r["nodes"] for r in results]
        xlabel = "Number of Nodes"

    elif x_type == "configs":
        x_values = [r["qm_calcs"] for r in results]
        xlabel = "Number of Configurations"

    else:
        raise ValueError(f"Invalid x_type: {x_type}")

    sorted_results = sorted(
        zip(x_values, results),
        key=lambda item: item[0],
    )

    x_values = [item[0] for item in sorted_results]
    data = [item[1] for item in sorted_results]

    stages = {
        "md": ("MD Sampling", "tab:blue"),
        "qm": ("QM Labeling", "tab:orange"),
        "ml": ("ML Training", "tab:green"),
    }

    fig, ax = plt.subplots(figsize=(8, 5))

    for stage, (label, color) in stages.items():

        percentages = [
            r[f"{stage}_percent"]
            for r in data
        ]

        ax.plot(
            x_values,
            percentages,
            "o-",
            linewidth=2,
            markersize=7,
            color=color,
            label=label,
        )

    ax.set_xlabel(xlabel)
    ax.set_ylabel("Fraction of Total Time (%)")
    ax.set_title("ALF Workflow Time Distribution")

    ax.set_ylim(0, 100)
    set_sparse_xticks(ax, x_values, max_ticks=6)

    ax.grid(True, alpha=0.3)
    ax.legend()

    fig.tight_layout()
    fig.savefig(output_file, dpi=300)
    plt.close(fig)


def main():

    parser = argparse.ArgumentParser(
        description="Compare ALF FOM across node counts."
    )

    parser.add_argument(
        "--alf_path",
        type=Path,
        default=Path.cwd(),
        help="Parent directory containing nodes_NMD_* folders.",
    )

    parser.add_argument(
        "--nodes",
        type=int,
        nargs="+",
        required=True,
        help="List of node counts to compare.",
    )

    parser.add_argument(
        "--timestep",
        type=float,
        default=0.25,
        help="MD timestep in fs (default: 0.25).",
    )

    parser.add_argument(
        "--md-duration",
        type=float,
        default=10.0,
        help="Target MD duration in ps (default: 10).",
    )

    parser.add_argument(
        "--epochs",
        type=int,
        default=500,
        help="Target ML epochs (default: 500).",
    )

    parser.add_argument(
        "--analyzer",
        type=Path,
        default=Path(__file__).resolve().parent
        / "analyze_FOM.py",
        help="Path to analyze_FOM.py.",
    )

    args = parser.parse_args()

    base_path = args.alf_path.expanduser().resolve()
    analyzer = args.analyzer.expanduser().resolve()

    if not base_path.is_dir():
        parser.error(f"Directory not found: {base_path}")

    if not analyzer.is_file():
        parser.error(f"Analyzer not found: {analyzer}")

    if any(n <= 0 for n in args.nodes):
        parser.error("Node counts must be positive.")

    if (
        not math.isfinite(args.timestep)
        or not math.isfinite(args.md_duration)
        or args.timestep <= 0
        or args.md_duration <= 0
    ):
        parser.error(
            "Timestep and MD duration must be finite positive numbers."
        )

    if args.epochs <= 0:
        parser.error("Epoch count must be positive.")

    results = []

    print("\nALF FOM Comparison")
    print("=" * 60)

    for nodes in sorted(set(args.nodes)):

        print(f"\nAnalyzing {nodes} nodes...")

        try:
            alf_dir = find_alf_directory(
                base_path, nodes
            )

            analysis = run_analysis(
                analyzer=analyzer,
                alf_dir=alf_dir,
                timestep=args.timestep,
                md_duration=args.md_duration,
                epochs=args.epochs,
            )

            analysis["nodes"] = nodes
            analysis["directory"] = alf_dir.name

            results.append(analysis)

            print(
                f"  Directory : {alf_dir.name}\n"
                f"  FOM       : {analysis['fom']:.0f}\n"
                f"  MD time   : {analysis['md_time']/3600:.3g} h\n"
                f"  QM time   : {analysis['qm_time']/3600:.3g} h\n"
                f"  ML time   : {analysis['ml_time']/3600:.3g} h"
            )

        except Exception as exc:
            print(f"  ERROR: {exc}", file=sys.stderr)
            continue

    if not results:
        parser.error("No successful analyses were found.")

    calculate_scaling(results)

    csv_file = base_path / "FOM_comparison.csv"
    fom_plot = base_path / "FOM_vs_nodes.png"
    efficiency_plot = (
        base_path / "FOM_scaling_efficiency.png"
    )

    save_csv(results, csv_file)
    plot_fom(results, fom_plot)
    plot_efficiency(results, efficiency_plot)

    # Stage execution times versus number of nodes
    for stage in ("md", "qm", "ml"):
        stage_plot = (
            base_path / f"{stage.upper()}_time_vs_nodes.png"
        )
        plot_stage_time(results, stage, stage_plot)

    # Stage execution times versus number of configurations
    for stage in ("md", "qm", "ml"):
        stage_plot = (
            base_path / f"{stage.upper()}_time_vs_configs.png"
        )
        plot_stage_configs(results, stage, stage_plot)

    # Stage percentage contributions
    for x_type in ("nodes", "configs"):
        output_file = (
            base_path / f"Stage_percent_vs_{x_type}.png"
        )
        plot_stage_percent(results, x_type, output_file)

    print("\n" + "=" * 60)
    print("Comparison Summary")
    print("=" * 60)

    print(
        f"{'Nodes':>8} "
        f"{'FOM':>14} "
        f"{'Ideal FOM':>14} "
        f"{'Efficiency':>12}"
    )

    for result in results:
        print(
            f"{result['nodes']:8d} "
            f"{result['fom']:14.0f} "
            f"{result['ideal_fom']:14.0f} "
            f"{result['efficiency_percent']:11.2f}%"
        )

    print("\nGenerated files:")
    print(f"  {csv_file}")
    print(f"  {fom_plot}")
    print(f"  {efficiency_plot}")

    for stage in ("md", "qm", "ml"):
        print(
            f"  {base_path / f'{stage.upper()}_time_vs_nodes.png'}"
        )

    for stage in ("md", "qm", "ml"):
        print(
            f"  {base_path / f'{stage.upper()}_time_vs_configs.png'}"
        )

    for x_type in ("nodes", "configs"):
        print(
            f"  {base_path / f'Stage_percent_vs_{x_type}.png'}"
        )

    print(
        "\nIndividual FOM_results.txt files are saved "
        "inside each analyzed ALF directory."
    )


if __name__ == "__main__":
    main()

