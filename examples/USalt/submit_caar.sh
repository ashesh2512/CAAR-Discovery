#!/bin/bash
#SBATCH --account=csc728
#SBATCH --job-name=alf_caar
#SBATCH --partition=batch
#SBATCH --nodes=18
#SBATCH --ntasks-per-node=56
#SBATCH --cpus-per-task=1
#SBATCH --time=00:10:00
#SBATCH --output=alf_caar_%j.out
#SBATCH --error=alf_caar_%j.err

set -eo pipefail

readonly NUMBER_OF_ALF_INSTANCES=983
readonly CAMPAIGN_DIR="${SLURM_SUBMIT_DIR:-$PWD}"
readonly ENVIRONMENT_SCRIPT="/lustre/orion/world-shared/csc728/messerlyra/scripts/load_caar_env.bash"

if [[ ! -f "${ENVIRONMENT_SCRIPT}" ]]; then
    echo "ERROR: Environment script not found: ${ENVIRONMENT_SCRIPT}" >&2
    exit 1
fi

# Loading the environment once here is sufficient. Environment variables,
# PATH changes, and loaded modules are inherited by all srun tasks.
source "${ENVIRONMENT_SCRIPT}"

if ! command -v python >/dev/null 2>&1; then
    echo "ERROR: Python is not available after loading ${ENVIRONMENT_SCRIPT}." >&2
    exit 1
fi

mapfile -t alf_directories < <(
    find "${CAMPAIGN_DIR}" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name 'alf_*' \
        -printf '%f\n' \
        | LC_ALL=C sort
)

if (( ${#alf_directories[@]} < NUMBER_OF_ALF_INSTANCES )); then
    echo "ERROR: Found only ${#alf_directories[@]} alf_* directories; ${NUMBER_OF_ALF_INSTANCES} are required." >&2
    exit 1
fi

system_list=$(mktemp "${CAMPAIGN_DIR}/.alf_systems_${SLURM_JOB_ID}.XXXXXX")
trap 'rm -f "${system_list}"' EXIT

printf '%s\n' "${alf_directories[@]:0:NUMBER_OF_ALF_INSTANCES}" > "${system_list}"

while IFS= read -r alf_directory; do
    if [[ ! -f "${CAMPAIGN_DIR}/${alf_directory}/master_config.json" ]]; then
        echo "ERROR: Missing master_config.json in ${CAMPAIGN_DIR}/${alf_directory}." >&2
        exit 1
    fi
done < "${system_list}"

export CAMPAIGN_DIR
export system_list

echo "Starting ${NUMBER_OF_ALF_INSTANCES} ALF instances on ${SLURM_NNODES} nodes."
echo "Campaign directory: ${CAMPAIGN_DIR}"

srun \
    --ntasks="${NUMBER_OF_ALF_INSTANCES}" \
    --ntasks-per-node=56 \
    --cpus-per-task=1 \
    --cpu-bind=cores \
    bash -c '
        set -eo pipefail

        line_number=$((SLURM_PROCID + 1))
        alf_directory=$(sed -n "${line_number}p" "${system_list}")

        if [[ -z "${alf_directory}" ]]; then
            echo "ERROR: No ALF directory assigned to task ${SLURM_PROCID}." >&2
            exit 1
        fi

        cd "${CAMPAIGN_DIR}/${alf_directory}"
        echo Running ALF in "${CAMPAIGN_DIR}/${alf_directory}"
        exec python -m alframework --master master_config.json \
            > "alf_master_${SLURM_JOB_ID}.out" 2>&1
    '

