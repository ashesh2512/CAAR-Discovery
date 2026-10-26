# `run_FOM.sh`

`run_FOM.sh` runs ALF FOM tests using different numbers of compute nodes.
By default, the tests run sequentially. The optional `--parallel` argument
starts all tests concurrently in the same `tmux` window.

## Configuration

Edit the node-count list near the beginning of the script:

```bash
NODE_COUNTS=(1 2 4 8)
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

The CAAR environment is activated before each ALF test inside the `tmux`
session. Without `--parallel`, all tests run in a single `tmux` window,
sequentially: the next test starts only after the previous ALF process exits.

If an ALF test exits with a nonzero exit code, the script stops and does not
start any remaining tests. This prevents later tests from running when the
failure may be caused by a shared configuration or environment problem.

With `--parallel`, all tests are started in the background using `&`. The
script waits for every test to finish and records each exit code in its own
log. A failure does not cancel tests that are already running.

## Running the Script

```bash
./run_FOM.sh
```

To run all node-count tests concurrently:

```bash
./run_FOM.sh --parallel
```

The script creates one detached `tmux` session with one window and keeps it
open after the tests finish or after a failure:

```bash
tmux attach -t alf_FOM
```

The ALF output is redirected to log files and is not printed in the `tmux`
window. Attach to the session only when you want to inspect its status; the
logs are the primary record of each test.

## Expected Output

For the default list, the following directories are created and tested in
order:

```text
FOM_runs/nodes_1
FOM_runs/nodes_2
FOM_runs/nodes_4
FOM_runs/nodes_8
```

For the example full list, the script prepares one directory for every value in
`NODE_COUNTS`. In the default mode, these tests are run in the listed order.
With `--parallel`, they are all started concurrently. Each directory contains
its own `master_FOM.json`, `frontier_FOM.py`, and log. For example:

```text
FOM_runs/nodes_1/alf_FOM_1_nodes.log
FOM_runs/nodes_8/alf_FOM_8_nodes.log
FOM_runs/nodes_1024/alf_FOM_1024_nodes.log
```

Each log records the start time, ALF output, and the final ALF exit code. In
sequential mode, if a test fails, its log contains the nonzero exit code and
later node-count tests are not started. In parallel mode, tests already
started continue independently.

