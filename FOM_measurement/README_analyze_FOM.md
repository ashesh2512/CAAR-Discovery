# analyze_FOM.py

A Python script to calculate the Figure of Merit (FOM) for the ALF workflow, defined as the **number of force components learned per hour**.

The script measures the original execution times of MD Sampling, QM Labeling, and ML Training, then extrapolates these times to the requested MD duration, number of QM batches, and number of ML epochs.

## Usage

Run from the main ALF directory:

```bash
python analyze_FOM.py
```

Or specify the ALF directory and simulation parameters:

```bash
python analyze_FOM.py \
    --alf_path /path/to/alf_directory \
    --timestep 0.1 \
    --md-duration 1000 \
    --epochs 500
```

## Arguments

| Argument | Default | Description |
|---|---|---|
| `--alf_path` | `PWD` | ALF directory containing `sampling/`, `QM/`, `ensembles/`, and `runinfo/` |
| `--timestep` | `0.1` | MD timestep in fs |
| `--md-duration` | `1000` | Target MD duration in ps |
| `--epochs` | `500` | Target number of ML training epochs |

## Methodology

**MD Sampling:** Measures the original MD execution time using file timestamps. Reads timing information from `sampling/*.p`, excludes the first 100 MD steps, and extrapolates the additional time required to reach the target MD duration.

**QM Labeling:** Counts completed QM calculations using `QM/mol-*/output.txt`. Determines the number of batches needed to label all MD trajectories and scales the original QM execution time accordingly.

**ML Training:** Reads `training_log.txt` from each model in the latest `ensembles/ensemble-*` directory. Uses the last recorded epoch time, averaged across models, to estimate the additional training time required to reach the target number of epochs.


## Figure of Merit

$$
\mathrm{FOM} = \frac{N_{\mathrm{QM}} \times N_{\mathrm{atoms}} \times 3}
{t_{\mathrm{MD}} + t_{\mathrm{QM}} + t_{\mathrm{ML}}} \times 3600
$$

Where:

- $N_{\mathrm{QM}}$ = completed QM calculations per batch × number of QM batches.
- $N_{\mathrm{atoms}}$ = number of atoms per configuration, obtained from the sampling pickle files.
- $t_{\mathrm{MD}}, t_{\mathrm{QM}}, t_{\mathrm{ML}}$ = extrapolated execution times in seconds.

**Output unit:** Force components learned per hour.

The script reports the original and extrapolated execution times, MD statistics, QM batch counts, ML epoch timings, and final FOM.
