#!/usr/bin/env bash

set -euo pipefail

# FOM node-count tests. These are MD node counts. Edit this list before running
# the script.
NODE_COUNTS=(1 2 4 8)
readonly GPUS_PER_NODE=8
# Number of configurations represented by the precomputed QM HDF5 file.
# This value must divide NCONFIGS_MD for every node count in NODE_COUNTS.
NCONFIGS_QM=512

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
readonly TEMPLATE_DIR="FOM_template_h5precomputed"
readonly OUTPUT_ROOT="FOM_runs_h5precomputed"
readonly ENVIRONMENT_SCRIPT="/lustre/orion/world-shared/csc728/messerlyra/scripts/load_caar_env.bash"
readonly TMUX_SESSION="alf_FOM_h5precomputed"
readonly MASTER_TEMPLATE="master_template.json"
readonly MASTER_CONFIG="master_FOM.json"
readonly FRONTIER_TEMPLATE="frontier_template.py"
readonly FRONTIER_CONFIG="frontier_FOM.py"
readonly H5_PRECOMPUTED_DIR="h5store_precomputed"

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

if (( NCONFIGS_QM == 0 || NCONFIGS_QM < -1 )); then
    echo "Error: NCONFIGS_QM must be positive or -1 (use NCONFIGS_MD)." >&2
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

    nnodes_md=$nodes
    nnodes_ml=1
    nconfigs_md=$((nnodes_md * GPUS_PER_NODE))
    if (( NCONFIGS_QM == -1 || NCONFIGS_QM > nconfigs_md )); then
        nconfigs_qm=$nconfigs_md
    else
        nconfigs_qm=$NCONFIGS_QM
    fi

    if (( nconfigs_md % nconfigs_qm != 0 )); then
        echo "Error: NCONFIGS_MD ($nconfigs_md) is not divisible by NCONFIGS_QM ($nconfigs_qm) for $nnodes_md MD node(s)." >&2
        exit 1
    fi
    if (( (nconfigs_qm * nnodes_md) % nconfigs_md != 0 )); then
        echo "Error: NNODES_QM is not an integer for $nnodes_md MD node(s); choose an NCONFIGS_QM compatible with GPUS_PER_NODE ($GPUS_PER_NODE)." >&2
        exit 1
    fi

    nconfigs_qm_minus_one=$((nconfigs_qm - 1))
    nconfigs_qm_plus_one=$((nconfigs_qm + 1))
    # ALF creates one new HDF5 file itself, so only the remaining files are
    # copied from the precomputed dataset.
    h5_copies=$((nconfigs_md / nconfigs_qm - 1))
    h5_precomputed_file="data-${nconfigs_qm}configs.h5"
    if (( h5_copies > 0 )) && [[ ! -f "$H5_PRECOMPUTED_DIR/$h5_precomputed_file" ]]; then
        echo "Error: precomputed HDF5 file not found: $H5_PRECOMPUTED_DIR/$h5_precomputed_file" >&2
        exit 1
    fi
    nnodes_qm=$((nnodes_md * nconfigs_qm / nconfigs_md))
    nconfigs_md_minus_one=$((nconfigs_md - 1))
    nconfigs_md_plus_one=$((nconfigs_md + 1))
    test_name="nodes_${nnodes_md}MD_${nnodes_qm}QM_${nnodes_ml}ML"
    test_dir="$OUTPUT_ROOT/$test_name"
    mkdir -p "$test_dir"

    # Copy the complete template, including hidden files.
    cp -a "$TEMPLATE_DIR/." "$test_dir/"

    # Keep a separate FOM master-config name in every test directory.
    mv -f "$test_dir/$MASTER_TEMPLATE" "$test_dir/$MASTER_CONFIG"
    mv -f "$test_dir/$FRONTIER_TEMPLATE" "$test_dir/$FRONTIER_CONFIG"

    # Replace resource-dependent placeholders in the copied configuration files.
    # The placeholders are deliberately plain text so that the resulting JSON
    # contains integer values rather than quoted strings.
    sed -i \
        -e "s/NNODES_QM/${nnodes_qm}/g" \
        -e "s/NNODES_MD/${nnodes_md}/g" \
        -e "s/NNODES_ML/${nnodes_ml}/g" \
        -e "s/NNODES/${nnodes_md}/g" \
        -e "s/NCONFIGS_QM_MINUS_ONE/${nconfigs_qm_minus_one}/g" \
        -e "s/NCONFIGS_QM_PLUS_ONE/${nconfigs_qm_plus_one}/g" \
        -e "s/NCONFIGS_QM/${nconfigs_qm}/g" \
        -e "s/NCONFIGS_MD_MINUS_ONE/${nconfigs_md_minus_one}/g" \
        -e "s/NCONFIGS_MD_PLUS_ONE/${nconfigs_md_plus_one}/g" \
        -e "s/NCONFIGS_MD/${nconfigs_md}/g" \
        "$test_dir/$FRONTIER_CONFIG" "$test_dir/$MASTER_CONFIG"

    mkdir -p "$test_dir/h5store"
    for ((h5_index = 0; h5_index < h5_copies; h5_index++)); do
        h5_name=$(printf 'data-%sconfigs-copy-%04d.h5' "$nconfigs_qm" "$h5_index")
        cp "$H5_PRECOMPUTED_DIR/$h5_precomputed_file" "$test_dir/h5store/$h5_name"
    done

done

# Start one detached tmux session. All tests use this one window.
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "Error: tmux session already exists: $TMUX_SESSION" >&2
    echo "Use: tmux attach -t $TMUX_SESSION" >&2
    exit 1
fi

tmux new-session -d -s "$TMUX_SESSION" -n "fom_tests"

node_counts_string="${NODE_COUNTS[*]}"
nnodes_qm_per_md=$((NCONFIGS_QM > 0 ? NCONFIGS_QM / GPUS_PER_NODE : 1))
if (( PARALLEL )); then
    command="set +e; failure=0; pids=(); for nodes in $node_counts_string; do if (( $NCONFIGS_QM == -1 || $NCONFIGS_QM > nodes * $GPUS_PER_NODE )); then nnodes_qm=\${nodes}; else nnodes_qm=$nnodes_qm_per_md; fi; test_name=\"nodes_\${nodes}MD_\${nnodes_qm}QM_1ML\"; test_dir=\"$PWD/$OUTPUT_ROOT/\${test_name}\"; log_path=\"\${test_dir}/alf_FOM_\${test_name}.log\"; { source '$ENVIRONMENT_SCRIPT' && export FOM_NODE_COUNT=\"\${nodes}\" && cd \"\${test_dir}\" && echo \"Starting FOM test with \${nodes} MD node(s), \${nnodes_qm} QM node(s), and 1 ML node at \$(date -Is)\" && python -u -m alframework --master master_FOM.json; status=\$?; echo \"ALF exit code: \${status}\"; exit \"\${status}\"; } > \"\${log_path}\" 2>&1 & pids+=(\$!); done; for pid in \"\${pids[@]}\"; do wait \"\${pid}\"; status=\$?; if (( status != 0 && failure == 0 )); then failure=\$status; fi; done; exec bash --noprofile --norc"
    run_mode="parallel"
else
    #command="set +e; failure=0; for nodes in $node_counts_string; do if (( $NCONFIGS_QM == -1 || $NCONFIGS_QM > nodes * $GPUS_PER_NODE )); then nnodes_qm=\${nodes}; else nnodes_qm=$nnodes_qm_per_md; fi; test_name=\"nodes_\${nodes}MD_\${nnodes_qm}QM_1ML\"; test_dir=\"$PWD/$OUTPUT_ROOT/\${test_name}\"; log_path=\"\${test_dir}/alf_FOM_\${test_name}.log\"; { source '$ENVIRONMENT_SCRIPT' && export FOM_NODE_COUNT=\"\${nodes}\" && cd \"\${test_dir}\" && echo \"Starting FOM test with \${nodes} MD node(s), \${nnodes_qm} QM node(s), and 1 ML node at \$(date -Is)\" && python -u -m alframework --master master_FOM.json; status=\$?; echo \"ALF exit code: \${status}\"; if (( status != 0 )); then failure=\$status; fi; } > \"\${log_path}\" 2>&1; if (( failure != 0 )); then break; fi; done; exec bash --noprofile --norc"
    command="set +e; failure=0; for nodes in $node_counts_string; do if (( $NCONFIGS_QM == -1 || $NCONFIGS_QM > nodes * $GPUS_PER_NODE )); then nnodes_qm=\${nodes}; else nnodes_qm=$nnodes_qm_per_md; fi; test_name=\"nodes_\${nodes}MD_\${nnodes_qm}QM_1ML\"; test_dir=\"$PWD/$OUTPUT_ROOT/\${test_name}\"; log_path=\"\${test_dir}/alf_FOM_\${test_name}.log\"; { source '$ENVIRONMENT_SCRIPT' && export FOM_NODE_COUNT=\"\${nodes}\" && cd \"\${test_dir}\" && echo \"Starting FOM test with \${nodes} MD node(s), \${nnodes_qm} QM node(s), and 1 ML node at \$(date -Is)\" && python -u -m alframework --master master_FOM.json; status=\$?; echo \"ALF exit code: \${status}\"; job_name=\"ML_\${nodes}nodes\"; mapfile -t job_ids < <(squeue -h -u messerlyra -n \"\${job_name}\" -o \"%A\"); if (( \${#job_ids[@]} > 0 )); then scancel \"\${job_ids[@]}\"; fi; sleep 2; if (( status != 0 )); then failure=\$status; fi; } > \"\${log_path}\" 2>&1; if (( failure != 0 )); then break; fi; done; exec bash --noprofile --norc"
    run_mode="sequential"
fi
tmux send-keys -t "$TMUX_SESSION:fom_tests" "$command" C-m

echo "Started ${#NODE_COUNTS[@]} $run_mode FOM tests in tmux session: $TMUX_SESSION"
echo "Attach with: tmux attach -t $TMUX_SESSION"
echo "List windows with: tmux list-windows -t $TMUX_SESSION"
echo "Logs are stored inside each test directory under: $OUTPUT_ROOT"

