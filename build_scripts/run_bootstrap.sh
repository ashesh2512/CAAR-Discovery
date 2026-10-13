#!/bin/bash

# Exit immediately if any command fails
set -e

echo "Loading CAAR environment..."
source /lustre/orion/world-shared/csc728/messerlyra/scripts/load_caar_env.bash

echo "Starting parallel execution of ALF systems..."

root_path="/lustre/orion/scratch/messerlyra/csc728/tests/alf_USalt/bootstrap_max2/"

cd "$root_path" || exit 1

# Loop through all files/folders starting with system_
for system in system_*; do
    # Check if it's actually a directory
    if [ -d "$system" ]; then

	# Check if any .h5 file already exists inside the h5store subfolder
        if ls "$system"/h5store/*.h5 1> /dev/null 2>&1; then
            echo "Skipping $system: Found existing .h5 file in h5store."
            continue
        fi

        echo "--------------------------------------------------"
        echo "Launching system in background: $system"
        echo "--------------------------------------------------"

        # Enter the directory, run Python unbuffered in the background, save the log, and exit back
        (
            cd "$system" || exit 1
            python -u -m alframework --master master_config.json > alf_log.log 2>&1 &
        )

	# Wait before launching the next system in the loop
        sleep 2s

    fi
done

echo "All systems have been launched in parallel!"
echo "Use 'ps aux | grep alframework' to monitor active processes."
