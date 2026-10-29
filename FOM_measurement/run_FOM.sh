#!/usr/bin/env bash

set -euo pipefail

# FOM node-count tests. Edit this list before running the script.
NODE_COUNTS=(1 2 4) #(1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192 9856)
readonly GPUS_PER_NODE=8

# By default, tests run sequentially. Use --parallel to start all tests
# concurrently in the same tmux window.
PARALLEL=0
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--parallel" ) ]]; then
    echo "Usage: $0 [--parallel]" >&2
    exit 1
fi
if [[ $# -eq 1 ]]; then
    PARALLEL=1
fi

# Paths and names.
readonly TEMPLATE_DIR="FOM_template"
readonly OUTPUT_ROOT="FOM_runs"
readonly ENVIRONMENT_SCRIPT="/lustre/orion/world-shared/csc728/messerlyra/scripts/load_caar_env.bash"
readonly TMUX_SESSION="alf_FOM"
readonly MASTER_TEMPLATE="master_template.json"
readonly MASTER_CONFIG="master_FOM.json"
readonly FRONTIER_TEMPLATE="frontier_template.py"
readonly FRONTIER_CONFIG="frontier_FOM.py"

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "Error: template directory not found: $TEMPLATE_DIR" >&2
    exit 1
fi

if [[ ! -f "$ENVIRONMENT_SCRIPT" ]]; then
    echo "Error: environment script not found: $ENVIRONMENT_SCRIPT" >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE_DIR/$MASTER_TEMPLATE" ]]; then
    echo "Error: $MASTER_TEMPLATE not found in $TEMPLATE_DIR" >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE_DIR/$FRONTIER_TEMPLATE" ]]; then
    echo "Error: $FRONTIER_TEMPLATE not found in $TEMPLATE_DIR" >&2
    exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
    echo "Error: tmux is not available." >&2
    exit 1
fi

if [[ ${#NODE_COUNTS[@]} -eq 0 ]]; then
    echo "Error: NODE_COUNTS is empty." >&2
    exit 1
fi

mkdir -p "$OUTPUT_ROOT"

# Prepare one independent directory for every node-count test.
for nodes in "${NODE_COUNTS[@]}"; do
    if [[ ! "$nodes" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: invalid node count: $nodes" >&2
        exit 1
    fi

    test_name="nodes_${nodes}"
    test_dir="$OUTPUT_ROOT/$test_name"
    mkdir -p "$test_dir"

    # Copy the complete template, including hidden files.
    cp -a "$TEMPLATE_DIR/." "$test_dir/"

    # Keep a separate FOM master-config name in every test directory.
    mv -f "$test_dir/$MASTER_TEMPLATE" "$test_dir/$MASTER_CONFIG"
    mv -f "$test_dir/$FRONTIER_TEMPLATE" "$test_dir/$FRONTIER_CONFIG"

    nconfigs=$((nodes * GPUS_PER_NODE))
    nconfigs_minus_one=$((nconfigs - 1))
    nconfigs_plus_one=$((nconfigs + 1))

    # Replace resource-dependent placeholders in the copied configuration files.
    # The placeholders are deliberately plain text so that the resulting JSON
    # contains integer values rather than quoted strings.
    sed -i \
        -e "s/NNODES/${nodes}/g" \
        -e "s/NCONFIGS_MINUS_ONE/${nconfigs_minus_one}/g" \
        -e "s/NCONFIGS_PLUS_ONE/${nconfigs_plus_one}/g" \
        -e "s/NCONFIGS/${nconfigs}/g" \
        "$test_dir/$FRONTIER_CONFIG" "$test_dir/$MASTER_CONFIG"

done

# Start one detached tmux session. All tests use this one window.
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Error: tmux session already exists: $TMUX_SESSION" >&2
    echo "Use: tmux attach -t $TMUX_SESSION" >&2
    exit 1
fi

tmux new-session -d -s "$TMUX_SESSION" -n "FOM_tests"

node_counts_string="${NODE_COUNTS[*]}"
if (( PARALLEL )); then
    command="set +e; failure=0; pids=(); for nodes in $node_counts_string; do test_dir=\"$PWD/$OUTPUT_ROOT/nodes_\${nodes}\"; log_path=\"\${test_dir}/alf_FOM_\${nodes}_nodes.log\"; { source '$ENVIRONMENT_SCRIPT' && export FOM_NODE_COUNT=\"\${nodes}\" && cd \"\${test_dir}\" && echo \"Starting FOM test with \${nodes} node(s) at \$(date -Is)\" && python -u -m alframework --master master_FOM.json; status=\$?; echo \"ALF exit code: \${status}\"; exit \"\${status}\"; } > \"\${log_path}\" 2>&1 & pids+=(\$!); done; for pid in \"\${pids[@]}\"; do wait \"\${pid}\"; status=\$?; if (( status != 0 && failure == 0 )); then failure=\$status; fi; done; exec bash --noprofile --norc"
    run_mode="parallel"
else
    command="set +e; failure=0; for nodes in $node_counts_string; do test_dir=\"$PWD/$OUTPUT_ROOT/nodes_\${nodes}\"; log_path=\"\${test_dir}/alf_FOM_\${nodes}_nodes.log\"; { source '$ENVIRONMENT_SCRIPT' && export FOM_NODE_COUNT=\"\${nodes}\" && cd \"\${test_dir}\" && echo \"Starting FOM test with \${nodes} node(s) at \$(date -Is)\" && python -u -m alframework --master master_FOM.json; status=\$?; echo \"ALF exit code: \${status}\"; job_name=\"ML_\${nodes}nodes\"; mapfile -t job_ids < <(squeue -h -u messerlyra -n \"\${job_name}\" -o \"%A\"); if (( \${#job_ids[@]} > 0 )); then scancel \"\${job_ids[@]}\"; fi; sleep 2; if (( status != 0 )); then failure=\$status; fi; } > \"\${log_path}\" 2>&1; if (( failure != 0 )); then break; fi; done; exec bash --noprofile --norc"
    run_mode="sequential"
fi
tmux send-keys -t "$TMUX_SESSION:FOM_tests" "$command" C-m

echo "Started ${#NODE_COUNTS[@]} $run_mode FOM tests in tmux session: $TMUX_SESSION"
echo "Attach with: tmux attach -t $TMUX_SESSION"
echo "List windows with: tmux list-windows -t $TMUX_SESSION"
echo "Logs are stored inside each test directory under: $OUTPUT_ROOT"

