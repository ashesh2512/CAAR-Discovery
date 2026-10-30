# `run_FOM.sh` — Precomputed HDF5 Version (Original)

`run_FOM.sh` runs ALF FOM tests using different numbers of MD compute nodes, with precomputed QM HDF5 data used to fill additional QM batches. By default, the tests run sequentially. The optional `--parallel` argument starts all tests concurrently in the same `tmux` window.

## Configuration

Edit the node-count list and QM configuration count near the beginning of the script:

```bash
NODE_COUNTS=(1 2 4 8)
NCONFIGS_QM=512
readonly GPUS_PER_NODE=8
# Example full list:
# NODE_COUNTS=(1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192 9856)
```

`NODE_COUNTS` specifies MD nodes. The number of MD configurations is `NCONFIGS_MD = NNODES_MD × 8`. `NCONFIGS_QM` is the maximum number of QM configurations in one batch; it is reduced to `NCONFIGS_MD` when larger. Set `NCONFIGS_QM=-1` to use `NCONFIGS_MD` for every test. The effective `NCONFIGS_QM` must divide `NCONFIGS_MD` exactly.

The script uses the following fixed paths and names:

```text
Template directory:       FOM_template
Output directory:         FOM_runs
Precomputed HDF5 directory: h5store_precomputed
Template master file:     master_template.json
Template Frontier file:   frontier_template.py
TMUX session:             alf_FOM
GPUs per node:            8
ML nodes per test:        1
```

The script does not accept template or output directories as command-line arguments. It also uses a fixed CAAR environment script path.

## What the Script Does

For each value in `NODE_COUNTS`, the script:

1. Sets `NNODES_MD` to the selected node count, `NNODES_ML` to 1, and computes `NNODES_QM = NCONFIGS_QM / 8` using the effective QM configuration count.
2. Computes `NCONFIGS_MD = NNODES_MD × 8` and the number of QM batches (`NCONFIGS_MD / NCONFIGS_QM`).
3. Copies `FOM_template` to `FOM_runs/nodes_<MD>MD_<QM>QM_1ML`.
4. Renames `master_template.json` to `master_FOM.json` and `frontier_template.py` to `frontier_FOM.py`.
5. Replaces resource placeholders in both files:

   ```text
   NNODES_MD, NNODES_QM, NNODES_ML, NNODES
   NCONFIGS_MD, NCONFIGS_MD_MINUS_ONE, NCONFIGS_MD_PLUS_ONE
   NCONFIGS_QM, NCONFIGS_QM_MINUS_ONE, NCONFIGS_QM_PLUS_ONE
   ```

6. Copies the precomputed `data-<NCONFIGS_QM>configs.h5` file into the test's `h5store/` directory **one fewer time than the number of QM batches**, because ALF creates one HDF5 file itself. Copies are named `data-<NCONFIGS_QM>configs-copy-0000.h5`, `...0001.h5`, etc. No precomputed file is needed when only one batch is required.
7. Runs ALF with:

   ```bash
   python -u -m alframework --master master_FOM.json
   ```

The CAAR environment is activated for each test. Without `--parallel`, tests run sequentially and the next test starts only after the preceding ALF process exits. After each sequential test, the script attempts to cancel leftover Slurm jobs named `ML_<MD nodes>nodes` for the configured user, then waits two seconds. A nonzero ALF exit code stops subsequent tests.

With `--parallel`, tests are launched in the background using `&` and waited on individually. Already-running tests are not canceled when another test fails. The sequential Slurm cleanup is not performed in parallel mode.

## Running the Script

```bash
./run_FOM.sh
```

To start all node-count tests concurrently:

```bash
./run_FOM.sh --parallel
```

The script creates one detached `tmux` session with one window and keeps it open after execution:

```bash
tmux attach -t alf_FOM
```

ALF output is redirected to a separate log in each test directory rather than printed in the `tmux` window.

## Expected Output

With the default `NODE_COUNTS=(1 2 4 8)` and `NCONFIGS_QM=512`, the effective QM node count equals the MD node count for these tests:

```text
FOM_runs/nodes_1MD_1QM_1ML
FOM_runs/nodes_2MD_2QM_1ML
FOM_runs/nodes_4MD_4QM_1ML
FOM_runs/nodes_8MD_8QM_1ML
```

Each directory contains its own `master_FOM.json`, `frontier_FOM.py`, `h5store/`, and log. For example:

```text
FOM_runs/nodes_8MD_8QM_1ML/alf_FOM_nodes_8MD_8QM_1ML.log
FOM_runs/nodes_1024MD_64QM_1ML/alf_FOM_nodes_1024MD_64QM_1ML.log
```

The second example assumes a test with 1024 MD nodes and 512 QM configurations per batch (64 QM nodes). Each log records the start message, ALF output, and final ALF exit code. In sequential mode, a failure prevents later tests from starting; in parallel mode, already-started tests continue independently.

