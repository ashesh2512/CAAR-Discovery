#!/usr/bin/env python3
"""Create ALF system folders from element combinations.

This script defines systems by the elements present, not by formal salt
recipes. Each system contains at least one cation and at least one anion.
"""

from __future__ import annotations

import argparse
import csv
import json
import shutil
from itertools import combinations
from pathlib import Path


DEFAULT_CATIONS = [
    "Li",
    "Na",
    "K",
    "Rb",
    "Cs",
    "Be",
    "Mg",
    "Ca",
    "Sr",
    "Ba",
    "Zn",
    "Zr",
]

DEFAULT_ANIONS = ["F", "Cl"]

DEFAULT_CHARGES = {
    "Li": 1,
    "Na": 1,
    "K": 1,
    "Rb": 1,
    "Cs": 1,
    "Be": 2,
    "Mg": 2,
    "Ca": 2,
    "Sr": 2,
    "Ba": 2,
    "Zn": 2,
    "Zr": 4,
    "F": -1,
    "Cl": -1,
}

ATOMIC_NUMBERS = {
    "Li": 3,
    "Be": 4,
    "F": 9,
    "Na": 11,
    "Mg": 12,
    "Cl": 17,
    "K": 19,
    "Ca": 20,
    "Zn": 30,
    "Rb": 37,
    "Zr": 40,
    "Sr": 38,
    "Cs": 55,
    "Ba": 56,
}


def parse_symbols(raw_symbols: str) -> list[str]:
    symbols = [symbol.strip() for symbol in raw_symbols.split(",")]
    symbols = [symbol for symbol in symbols if symbol]
    if not symbols:
        raise ValueError("At least one symbol is required.")
    if len(symbols) != len(set(symbols)):
        raise ValueError(f"Duplicate symbols found in: {raw_symbols}")
    return symbols


def make_folder_name(
    system_id: int,
    total_elements: int,
    cations: tuple[str, ...],
    anions: tuple[str, ...],
) -> str:
    cation_label = "-".join(cations)
    anion_label = "-".join(anions)
    return f"system_{system_id:06d}_n{total_elements:02d}_c-{cation_label}_a-{anion_label}"


def make_element_tag(cations: tuple[str, ...], anions: tuple[str, ...]) -> str:
    return "_".join([*cations, *anions])


def iter_systems(
    cations: list[str],
    anions: list[str],
    min_elements: int,
    max_elements: int,
):
    system_id = 0
    for total_elements in range(min_elements, max_elements + 1):
        for n_anions in range(1, min(len(anions), total_elements - 1) + 1):
            n_cations = total_elements - n_anions
            if n_cations < 1 or n_cations > len(cations):
                continue
            for cation_combo in combinations(cations, n_cations):
                for anion_combo in combinations(anions, n_anions):
                    system_id += 1
                    yield {
                        "system_id": system_id,
                        "total_elements": total_elements,
                        "n_cations": n_cations,
                        "n_anions": n_anions,
                        "cations": cation_combo,
                        "anions": anion_combo,
                    }


def copy_template(template_dir: Path, destination: Path) -> None:
    for item in template_dir.iterdir():
        target = destination / item.name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True)
        else:
            shutil.copy2(item, target)


def recursive_replace_key(data, target_key: str, replacement) -> int:
    replacements = 0
    if isinstance(data, dict):
        for key, value in data.items():
            if key == target_key:
                data[key] = replacement
                replacements += 1
            else:
                replacements += recursive_replace_key(value, target_key, replacement)
    elif isinstance(data, list):
        for item in data:
            replacements += recursive_replace_key(item, target_key, replacement)
    return replacements


def update_json_file(json_path: Path, replacements: dict[str, object]) -> dict[str, int]:
    if not json_path.exists():
        return {key: -1 for key in replacements}

    with json_path.open("r") as input_file:
        data = json.load(input_file)

    replacement_counts = {}
    for key, replacement in replacements.items():
        replacement_counts[key] = recursive_replace_key(data, key, replacement)

    with json_path.open("w") as output_file:
        json.dump(data, output_file, indent=2)
        output_file.write("\n")

    return replacement_counts


def species_for_hippynn(elements: list[str], species_format: str) -> list[str] | list[int]:
    if species_format == "symbols":
        return [0, *elements]
    if species_format == "atomic_numbers":
        missing = [element for element in elements if element not in ATOMIC_NUMBERS]
        if missing:
            raise ValueError(f"Missing atomic numbers for: {', '.join(missing)}")
        return [0, *[ATOMIC_NUMBERS[element] for element in elements]]
    raise ValueError(f"Unknown species format: {species_format}")


def charges_for_builder(elements: list[str], charge_format: str) -> dict[str, int] | list[int]:
    missing = [element for element in elements if element not in DEFAULT_CHARGES]
    if missing:
        raise ValueError(f"Missing charges for: {', '.join(missing)}")

    if charge_format == "dict":
        return {element: DEFAULT_CHARGES[element] for element in elements}
    if charge_format == "list":
        return [DEFAULT_CHARGES[element] for element in elements]
    raise ValueError(f"Unknown charge format: {charge_format}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create folders for ALF systems defined by element combinations."
    )
    parser.add_argument(
        "--output-dir",
        default="alf_element_systems",
        help="Directory where system folders and the manifest will be written.",
    )
    parser.add_argument(
        "--min-elements",
        type=int,
        default=2,
        help="Minimum number of elements in a system.",
    )
    element_count_group = parser.add_mutually_exclusive_group()
    element_count_group.add_argument(
        "--max-elements",
        type=int,
        default=None,
        help="Maximum number of elements in a system. Defaults to all configured elements.",
    )
    element_count_group.add_argument(
        "--num-elements",
        type=int,
        default=None,
        help="Create only systems with exactly this number of elements.",
    )
    parser.add_argument(
        "--cations",
        default=",".join(DEFAULT_CATIONS),
        help="Comma-separated cation symbols.",
    )
    parser.add_argument(
        "--anions",
        default=",".join(DEFAULT_ANIONS),
        help="Comma-separated anion symbols.",
    )
    parser.add_argument(
        "--template-dir",
        default=None,
        help="Optional directory to copy into every system folder.",
    )
    parser.add_argument(
        "--builder-config-name",
        default="builder_config.json",
        help="Builder JSON file to update inside each system folder.",
    )
    parser.add_argument(
        "--builder-elements-key",
        default=None,
        help="Optional JSON key to replace with the element list in builder_config.json.",
    )
    parser.add_argument(
        "--builder-charges-key",
        default="atom_charges",
        help="JSON key to replace with per-element charges in builder_config.json.",
    )
    parser.add_argument(
        "--builder-charges-format",
        choices=["dict", "list"],
        default="dict",
        help="Format to write for charges in builder_config.json.",
    )
    parser.add_argument(
        "--hippynn-config-name",
        default="hippynn_config.json",
        help="HIP-NN JSON file to update inside each system folder.",
    )
    parser.add_argument(
        "--hippynn-species-key",
        default="possible_species",
        help="JSON key to replace in hippynn_config.json.",
    )
    parser.add_argument(
        "--hippynn-species-format",
        choices=["atomic_numbers", "symbols"],
        default="atomic_numbers",
        help="Format to write for possible_species.",
    )
    parser.add_argument(
        "--update-hippynn-config",
        action="store_true",
        help="Update possible_species in hippynn_config.json. Disabled by default.",
    )
    parser.add_argument(
        "--master-config-name",
        default="master_config.json",
        help="Master JSON file to update inside each system folder.",
    )
    parser.add_argument(
        "--h5-path-key",
        default="h5_path",
        help="JSON key to replace in master_config.json.",
    )
    parser.add_argument(
        "--h5-path-prefix",
        default="h5store/data",
        help="Prefix for per-system h5_path values.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print counts and example folder names without creating folders.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Optional maximum number of systems to create or show.",
    )
    args = parser.parse_args()

    cations = parse_symbols(args.cations)
    anions = parse_symbols(args.anions)
    if args.num_elements is not None:
        args.min_elements = args.num_elements
        args.max_elements = args.num_elements
    elif args.max_elements is None:
        args.max_elements = len(cations) + len(anions)

    if args.min_elements < 2:
        raise ValueError("--min-elements must be at least 2.")
    if args.max_elements < args.min_elements:
        raise ValueError("--max-elements must be greater than or equal to --min-elements.")

    output_dir = Path(args.output_dir)
    template_dir = Path(args.template_dir) if args.template_dir else None
    if template_dir is not None and not template_dir.is_dir():
        raise ValueError(f"Template directory does not exist: {template_dir}")

    systems = []
    counts_by_size: dict[int, int] = {}
    for system in iter_systems(cations, anions, args.min_elements, args.max_elements):
        if args.limit is not None and len(systems) >= args.limit:
            break
        systems.append(system)
        counts_by_size[system["total_elements"]] = counts_by_size.get(system["total_elements"], 0) + 1

    print("System counts:")
    for total_elements in range(args.min_elements, args.max_elements + 1):
        print(f"  {total_elements} elements: {counts_by_size.get(total_elements, 0)}")
    print(f"  total: {len(systems)}")

    print("\nExample folder names:")
    for system in systems[:10]:
        folder_name = make_folder_name(
            system["system_id"],
            system["total_elements"],
            system["cations"],
            system["anions"],
        )
        print(f"  {folder_name}")

    if args.dry_run:
        print("\nDry run requested; no folders were created.")
        return

    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "systems_manifest.csv"

    with manifest_path.open("w", newline="") as manifest_file:
        writer = csv.DictWriter(
            manifest_file,
            fieldnames=[
                "system_id",
                "folder",
                "total_elements",
                "n_cations",
                "n_anions",
                "cations",
                "anions",
                "elements",
                "charges",
                "h5_path",
                "hippynn_possible_species",
            ],
        )
        writer.writeheader()

        for system in systems:
            folder_name = make_folder_name(
                system["system_id"],
                system["total_elements"],
                system["cations"],
                system["anions"],
            )
            system_dir = output_dir / folder_name
            system_dir.mkdir(parents=True, exist_ok=True)

            if template_dir is not None:
                copy_template(template_dir, system_dir)

            elements = list(system["cations"]) + list(system["anions"])
            element_tag = make_element_tag(system["cations"], system["anions"])
            builder_replacements = {
                args.builder_charges_key: charges_for_builder(
                    elements,
                    args.builder_charges_format,
                ),
            }
            if args.builder_elements_key is not None:
                builder_replacements[args.builder_elements_key] = elements
            builder_counts = update_json_file(system_dir / args.builder_config_name, builder_replacements)
            master_counts = update_json_file(
                system_dir / args.master_config_name,
                {args.h5_path_key: f"{args.h5_path_prefix}-{element_tag}-{{:04d}}.h5"},
            )

            if args.builder_elements_key is not None and builder_counts[args.builder_elements_key] == 0:
                print(
                    f"Warning: did not find key '{args.builder_elements_key}' in "
                    f"{system_dir / args.builder_config_name}"
                )
            if builder_counts[args.builder_charges_key] == 0:
                print(
                    f"Warning: did not find key '{args.builder_charges_key}' in "
                    f"{system_dir / args.builder_config_name}"
                )
            if master_counts[args.h5_path_key] == 0:
                print(
                    f"Warning: did not find key '{args.h5_path_key}' in "
                    f"{system_dir / args.master_config_name}"
                )
            if args.update_hippynn_config:
                hippynn_counts = update_json_file(
                    system_dir / args.hippynn_config_name,
                    {
                        args.hippynn_species_key: species_for_hippynn(
                            elements,
                            args.hippynn_species_format,
                        )
                    },
                )
                if hippynn_counts[args.hippynn_species_key] == 0:
                    print(
                        f"Warning: did not find key '{args.hippynn_species_key}' in "
                        f"{system_dir / args.hippynn_config_name}"
                    )

            writer.writerow(
                {
                    "system_id": system["system_id"],
                    "folder": folder_name,
                    "total_elements": system["total_elements"],
                    "n_cations": system["n_cations"],
                    "n_anions": system["n_anions"],
                    "cations": " ".join(system["cations"]),
                    "anions": " ".join(system["anions"]),
                    "elements": " ".join(elements),
                    "charges": " ".join(str(DEFAULT_CHARGES[element]) for element in elements),
                    "h5_path": f"{args.h5_path_prefix}-{element_tag}-{{:04d}}.h5",
                    "hippynn_possible_species": (
                        "not_updated"
                        if not args.update_hippynn_config
                        else " ".join(
                            str(species)
                            for species in species_for_hippynn(elements, args.hippynn_species_format)
                        )
                    ),
                }
            )

    print(f"\nCreated {len(systems)} system folders in: {output_dir}")
    print(f"Wrote manifest: {manifest_path}")


if __name__ == "__main__":
    main()

