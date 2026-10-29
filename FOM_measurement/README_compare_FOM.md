# compare_FOM.py

A Python script to compare the Figure of Merit (FOM) and execution times of the Active Learning Framework (ALF) across different node counts and numbers of configurations.

The script runs `analyze_FOM.py` for each ALF directory, collects the results, and generates a CSV summary and scaling plots.

## Requirements

- Python 3
- Matplotlib
- `analyze_FOM.py` (in the same directory, or specified using `--analyzer`)

Each ALF run directory must contain the required `sampling/`, `QM/`, `ensembles/`, and `runinfo/` directories.

## Usage

Run with default parameters:

```bash
python compare_FOM.py \
    --alf_path /path/to/experiments \
    --nodes 1 2 4 8 16 32 64 128 256 512
```

Or specify the MD and ML parameters:

```bash
python compare_FOM.py \
    --alf_path /path/to/experiments \
    --nodes 1 2 4 8 16 32 64 128 256 512 \
    --timestep 0.25 \
    --md-duration 10 \
    --epochs 500
```

The script searches for directories matching `nodes_NMD_*`, where `N` is the number of MD nodes (e.g., `nodes_512MD_64QM_1ML`).

## Arguments

| Argument | Default | Description |
|---|---|---|
| `--alf_path` | `PWD` | Parent directory containing the ALF runs |
| `--nodes` | Required | List of MD node counts to compare |
| `--timestep` | `0.25` | MD timestep in fs |
| `--md-duration` | `10` | Target MD duration in ps |
| `--epochs` | `500` | Target number of ML training epochs |
| `--analyzer` | `analyze_FOM.py` | Path to the FOM analysis script |

## Methodology

For each node count, the script:

1. Finds the corresponding ALF directory.
2. Runs `analyze_FOM.py` and saves its output to `FOM_results.txt` inside that directory.
3. Extracts the FOM, extrapolated MD/QM/ML execution times, and configuration counts.
4. Calculates the percentage of total execution time spent on each stage.
5. Compares the measured FOM against ideal linear scaling.

The FOM scaling efficiency is calculated as:

$$
\mathrm{Efficiency}(\%) =
\frac{\mathrm{FOM}_{\mathrm{measured}}}
{\mathrm{FOM}_{\mathrm{ideal}}}\times100
$$

The ideal FOM is obtained by scaling the FOM of the smallest successfully analyzed node count linearly with the number of nodes.

## Outputs

### CSV Summary

`FOM_comparison.csv` contains:

- Node count and ALF directory name
- Number of MD trajectories and extrapolated QM calculations
- Measured FOM, ideal FOM, and scaling efficiency
- Extrapolated MD, QM, ML, and total execution times (hours)
- Percentage of total execution time contributed by each stage

### Figures

| File | Description |
|---|---|
| `FOM_vs_nodes.png` | Measured FOM vs. ideal linear scaling |
| `FOM_scaling_efficiency.png` | FOM scaling efficiency (%) |
| `MD_time_vs_nodes.png` | MD execution time vs. number of nodes |
| `QM_time_vs_nodes.png` | QM execution time vs. number of nodes |
| `ML_time_vs_nodes.png` | ML execution time vs. number of nodes |
| `MD_time_vs_configs.png` | MD execution time vs. number of configurations |
| `QM_time_vs_configs.png` | QM execution time vs. number of configurations |
| `ML_time_vs_configs.png` | ML execution time vs. number of configurations |
| `Stage_percent_vs_nodes.png` | MD/QM/ML contributions (%) vs. number of nodes |
| `Stage_percent_vs_configs.png` | MD/QM/ML contributions (%) vs. number of configurations |

All execution-time plots use extrapolated times. Configuration-based plots use the extrapolated number of QM calculations. Time-percentage plots show the three stages separately, with the vertical axis ranging from 0% to 100%.

Figures are saved as PNG files in the parent ALF directory.

## Notes

- If an analysis fails, the script reports the error and continues with the remaining directories.
- Each node count must match exactly one ALF directory.
- The CSV uses 3 significant figures for hours, 5 significant figures for percentages, and integer values for FOM.
- The `FOM_results.txt` files preserve the output of `analyze_FOM.py`.
- Scaling efficiency is calculated for the overall FOM, not for individual MD, QM, or ML stages.
