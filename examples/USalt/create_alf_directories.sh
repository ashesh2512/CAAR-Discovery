#!/usr/bin/env bash

set -euo pipefail

# Usage:
#   ./create_alf_directories.sh [output_directory] [boilerplate_directory]
#
# By default, create the alf_* directories in the current directory and copy files from
# ./alf_moltensalt_boilerplate.
output_root="${1:-.}"
boilerplate_dir="${2:-alf_moltensalt_boilerplate}"

if [[ ! -d "$boilerplate_dir" ]]; then
    echo "Error: boilerplate directory '$boilerplate_dir' does not exist." >&2
    exit 1
fi

mkdir -p -- "$output_root"

# Group 1 and group 2 cations included in this campaign.
monovalent_cations=(Li Na K Rb Cs)
divalent_cations=(Be Mg Ca Sr)
anions=(F Cl)

# Build the list of 20 salts, with fluorides followed by chlorides.
salts=()
for anion in "${anions[@]}"; do
    for cation in "${monovalent_cations[@]}"; do
        salts+=("${cation}${anion}")
    done

    for cation in "${divalent_cations[@]}"; do
        salts+=("${cation}${anion}2")
    done
done

number_of_salts=${#salts[@]}
unary_count=0
binary_count=0
ternary_count=0

# Properties required to build atom_charges and possible_species.
declare -A element_charges=(
    [F]=-1 [Cl]=-1
    [Li]=1 [Na]=1 [K]=1 [Rb]=1 [Cs]=1
    [Be]=2 [Mg]=2 [Ca]=2 [Sr]=2 [Ba]=2
)

declare -A atomic_numbers=(
    [Li]=3 [Be]=4 [F]=9 [Na]=11 [Mg]=12 [Cl]=17
    [K]=19 [Ca]=20 [Rb]=37 [Sr]=38 [Cs]=55 [Ba]=56
)

# Increasing atomic-number order. The same order is used in both files;
# it is required only to keep possible_species naturally ordered.
element_order=(Li Be F Na Mg Cl K Ca Rb Sr Cs Ba)

create_alf_directory() {
    local directory_name="$1"
    shift
    local salts_in_system=("$@")
    local directory_path="${output_root}/${directory_name}"

    if [[ -e "$directory_path" && ! -d "$directory_path" ]]; then
        echo "Error: '$directory_path' already exists but is not a directory." >&2
        exit 1
    fi

    # -p allows the script to run again without deleting existing directories.
    mkdir -p -- "$directory_path"

    # Copy hidden files as well. -n protects files that already exist if the
    # script is run again.
    cp -a -n -- "${boilerplate_dir}/." "${directory_path}/"

    modify_config_files \
        "${directory_path}/builder_config.json" \
        "${directory_path}/hippynn_config.json" \
        "${salts_in_system[@]}"
}

modify_config_files() {
    local builder_config_path="$1"
    local hippynn_config_path="$2"
    shift 2

    local config_path
    for config_path in "$builder_config_path" "$hippynn_config_path"; do
        if [[ ! -f "$config_path" ]]; then
            echo "Error: file not found: $config_path" >&2
            exit 1
        fi
    done

    local -A elements_in_system=()
    local salt
    local cation
    local anion

    for salt in "$@"; do
        if [[ "$salt" =~ ^(Li|Na|K|Rb|Cs|Be|Mg|Ca|Sr|Ba)(F|Cl)2?$ ]]; then
            cation="${BASH_REMATCH[1]}"
            anion="${BASH_REMATCH[2]}"
            elements_in_system["$cation"]=1
            elements_in_system["$anion"]=1
        else
            echo "Error: unrecognized salt formula: $salt" >&2
            exit 1
        fi
    done

    local atom_charges_json="{"
    local separator=""
    local element

    for element in "${element_order[@]}"; do
        if [[ -n "${elements_in_system[$element]+x}" ]]; then
            atom_charges_json+="${separator}\"${element}\": ${element_charges[$element]}"
            separator=","
        fi
    done
    atom_charges_json+="}"

    local possible_species_json="[0"
    for element in "${element_order[@]}"; do
        if [[ -n "${elements_in_system[$element]+x}" ]]; then
            possible_species_json+=", ${atomic_numbers[$element]}"
        fi
    done
    possible_species_json+="]"

    local builder_matches
    local hippynn_matches
    builder_matches=$(grep -Ec '"atom_charges"[[:space:]]*:[[:space:]]*\{[^{}]*\}' "$builder_config_path" || true)
    hippynn_matches=$(grep -Ec '"possible_species"[[:space:]]*:[[:space:]]*\[[^]]*\]' "$hippynn_config_path" || true)

    if ((builder_matches != 1)); then
        echo "Error: atom_charges was not found exactly once in $builder_config_path" >&2
        exit 1
    fi
    if ((hippynn_matches != 1)); then
        echo "Error: possible_species was not found exactly once in $hippynn_config_path" >&2
        exit 1
    fi

    # Modify only the atom_charges object and the possible_species list.
    sed -E -i \
        "s|(\"atom_charges\"[[:space:]]*:[[:space:]]*)\{[^{}]*\}|\\1${atom_charges_json}|" \
        "$builder_config_path"

    sed -E -i \
        "s|(\"possible_species\"[[:space:]]*:[[:space:]]*)\[[^]]*\]|\\1${possible_species_json}|" \
        "$hippynn_config_path"
}

# Unary systems: 20.
for salt in "${salts[@]}"; do
    create_alf_directory "alf_${salt}" "$salt"
    ((unary_count += 1))
done

# Unique binary systems: i < j, so A_B is created but B_A is not.
for ((i = 0; i < number_of_salts; i++)); do
    for ((j = i + 1; j < number_of_salts; j++)); do
        create_alf_directory \
            "alf_${salts[i]}_${salts[j]}" \
            "${salts[i]}" "${salts[j]}"
        ((binary_count += 1))
    done
done

# Unique ternary systems: i < j < k, avoiding repetitions and permutations.
for ((i = 0; i < number_of_salts; i++)); do
    for ((j = i + 1; j < number_of_salts; j++)); do
        for ((k = j + 1; k < number_of_salts; k++)); do
            create_alf_directory \
                "alf_${salts[i]}_${salts[j]}_${salts[k]}" \
                "${salts[i]}" "${salts[j]}" "${salts[k]}"
            ((ternary_count += 1))
        done
    done
done

total_count=$((unary_count + binary_count + ternary_count))
expected_total=987

printf 'Unary directories:  %d\n' "$unary_count"
printf 'Binary directories: %d\n' "$binary_count"
printf 'Ternary directories: %d\n' "$ternary_count"
printf 'Total:               %d\n' "$total_count"

if ((total_count != expected_total)); then
    echo "Error: expected ${expected_total} combinations." >&2
    exit 1
fi

echo "All combinations were processed in: ${output_root}"

