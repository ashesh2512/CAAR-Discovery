# `run_FOM.sh`

`run_FOM.sh` runs ALF FOM tests using different numbers of compute nodes.

## Configuration

Edit the node-count list near the beginning of the script:

```bash
NODE_COUNTS=(1)
# Example full list:
# NODE_COUNTS=(1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192 9856)
```

The script uses the following fixed paths and names:

```text
Template directory:       FOM_template
Output directory:         FOM_runs
Template master file:     master_template.json
Template Frontier file:   frontier_template.py
TMUX session:             alf_FOM
GPUs per node:            8
```

The script does not accept template or output directories as command-line
arguments.

## What the Script Does

For each value in `NODE_COUNTS`, the script:

1. Copies `FOM_template` to `FOM_runs/nodes_<N>`.
2. Renames `master_template.json` to `master_FOM.json`.
3. Renames `frontier_template.py` to `frontier_FOM.py`.
4. Replaces the resource placeholders in both files:

   ```text
   NNODES              = N
   NCONFIGS            = N × 8
   NCONFIGS_MINUS_ONE  = NCONFIGS - 1
   NCONFIGS_PLUS_ONE   = NCONFIGS + 1
   ```

5. Runs ALF with:

   ```bash
   python -u -m alframework --master master_FOM.json
   ```

The CAAR environment is activated inside each `tmux` window. Each node-count
test runs in its own window, so the tests are submitted in parallel.

## Running the Script

```bash
./run_fom.sh
```

The script creates one `tmux` session and keeps it open after all tests finish:

```bash
tmux attach -t alf_FOM
```

The ALF output is redirected to log files and is not printed in the `tmux`
window.

## Expected Output

For the default list, the following directory is created:

```text
FOM_runs/nodes_1
```

For the example full list, the script creates one directory for every value in
`NODE_COUNTS`. Each directory contains its own `master_FOM.json`,
`frontier_FOM.py`, and log. For example:

```text
FOM_runs/nodes_1/alf_FOM_1_nodes.log
FOM_runs/nodes_8/alf_FOM_8_nodes.log
FOM_runs/nodes_1024/alf_FOM_1024_nodes.log
```

Each log records the start time, ALF output, and the final ALF exit code.

