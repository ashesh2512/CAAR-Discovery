#!/usr/bin/env bash

set -euo pipefail

# FOM node-count tests. Edit this list before running the script.
NODE_COUNTS=(1) #(1 2 4 8 16 32 64 128 256 512 1024 2048 4096 8192 9856)
readonly GPUS_PER_NODE=8

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

# Start a detached tmux session. Every test runs in its own window.
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Error: tmux session already exists: $TMUX_SESSION" >&2
    echo "Use: tmux attach -t $TMUX_SESSION" >&2
    exit 1
fi

tmux new-session -d -s "$TMUX_SESSION" -n "setup"
tmux send-keys -t "$TMUX_SESSION:setup" "echo 'FOM session started: $TMUX_SESSION'" C-m

first_test=1
for nodes in "${NODE_COUNTS[@]}"; do
    if [[ ! "$nodes" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: invalid node count: $nodes" >&2
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
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

    if (( first_test )); then
        window="$test_name"
        tmux rename-window -t "$TMUX_SESSION:setup" "$window"
        first_test=0
    else
        tmux new-window -t "$TMUX_SESSION" -n "$test_name"
        window="$test_name"
    fi

    log_file="alf_FOM_${nodes}_nodes.log"
    log_path="$PWD/$test_dir/$log_file"
    command="{ source '$ENVIRONMENT_SCRIPT' && export FOM_NODE_COUNT='$nodes' && cd '$PWD/$test_dir' && echo \"Starting FOM test with $nodes node(s) at \$(date -Is)\" && python -u -m alframework --master master_FOM.json; status=\$?; echo \"ALF exit code: \$status\"; } > '$log_path' 2>&1; exec bash --noprofile --norc"
    tmux send-keys -t "$TMUX_SESSION:$window" "$command" C-m

done

echo "Started ${#NODE_COUNTS[@]} FOM tests in tmux session: $TMUX_SESSION"
echo "Attach with: tmux attach -t $TMUX_SESSION"
echo "List windows with: tmux list-windows -t $TMUX_SESSION"
echo "Logs are stored inside each test directory under: $OUTPUT_ROOT"

