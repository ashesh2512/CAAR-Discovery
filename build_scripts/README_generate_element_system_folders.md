# `generate_element_system_folders.py`

Create ALF input folders for molten-salt systems defined by element combinations.

The script enumerates systems from a set of cations and anions, copies a boilerplate
directory into each system folder, and updates selected JSON configuration fields.
Each generated system contains at least one cation and at least one anion.

## Default Chemical Space

By default, the script uses 10 cations and 2 anions:

```text
Cations: Li, Na, K, Rb, Cs, Be, Mg, Ca, Sr, Ba
Anions:  F, Cl
```

This gives 12 total elements and 3,069 possible element-defined systems.

## Basic Usage

Preview all systems without creating folders:

```bash
python generate_element_system_folders.py --dry-run
```

Create all systems:

```bash
python generate_element_system_folders.py \
    --output-dir alf_element_systems \
    --template-dir alf_moltensalt_boilerplate
```

Create systems up to a maximum number of elements:

```bash
python generate_element_system_folders.py \
    --output-dir alf_element_systems_max5 \
    --template-dir alf_moltensalt_boilerplate \
    --max-elements 5
```

Create only systems with exactly one number of elements:

```bash
python generate_element_system_folders.py \
    --output-dir alf_element_systems_n5 \
    --template-dir alf_moltensalt_boilerplate \
    --num-elements 5
```

`--max-elements` and `--num-elements` are mutually exclusive.

## Expected Counts

With the default 10 cations and 2 anions:

| Elements per system | Number of systems |
|---:|---:|
| 2 | 20 |
| 3 | 100 |
| 4 | 285 |
| 5 | 540 |
| 6 | 714 |
| 7 | 672 |
| 8 | 450 |
| 9 | 210 |
| 10 | 65 |
| 11 | 12 |
| 12 | 1 |

Total:

```text
3,069 systems
```

Systems up to 5 elements:

```text
20 + 100 + 285 + 540 = 945 systems
```

## Folder Names

Folder names encode the system ID, number of elements, cations, and anions.

Example:

```text
system_000118_n03_c-Ca_a-F-Cl
```

This means:

```text
system_id = 118
number of elements = 3
cations = Ca
anions = F, Cl
```

## Files Copied From the Template

If `--template-dir` is provided, every file and subdirectory from the template is
copied into each generated system folder.

Example:

```bash
--template-dir alf_moltensalt_boilerplate
```

## JSON Updates

### `builder_config.json`

The script updates the `atom_charges` entry.

For example, for a Ca/F/Cl system:

```json
"atom_charges": {
  "Ca": 2,
  "F": -1,
  "Cl": -1
}
```

Default charges:

```text
Li, Na, K, Rb, Cs -> +1
Be, Mg, Ca, Sr, Ba -> +2
F, Cl -> -1
```

If the key is not called `atom_charges`, use:

```bash
--builder-charges-key YOUR_KEY
```

By default, charges are written as a dictionary. To write a list instead:

```bash
--builder-charges-format list
```

### `master_config.json`

The script updates `h5_path` to include the element list.

For example:

```json
"h5_path": "h5store/data-Li_Na_F-{:04d}.h5"
```

The default prefix is:

```text
h5store/data
```

To change it:

```bash
--h5-path-prefix YOUR_PREFIX
```

If the key is not called `h5_path`, use:

```bash
--h5-path-key YOUR_KEY
```

### `hippynn_config.json`

By default, the script does **not** modify `possible_species`.

This is intentional when using one global HIP-NN model for all systems. In that
case, set `possible_species` once in the boilerplate `hippynn_config.json`.

For the default 12-element space, the global `possible_species` list is:

```json
"possible_species": [0, 3, 4, 9, 11, 12, 17, 19, 20, 37, 38, 55, 56]
```

This corresponds to:

```text
0, Li, Be, F, Na, Mg, Cl, K, Ca, Rb, Sr, Cs, Ba
```

To update `possible_species` separately for each system, use:

```bash
--update-hippynn-config
```

For example, a Li/F system would then get:

```json
"possible_species": [0, 3, 9]
```

## Manifest

The script writes a CSV manifest:

```text
systems_manifest.csv
```

The manifest contains:

```text
system_id
folder
total_elements
n_cations
n_anions
cations
anions
elements
charges
h5_path
hippynn_possible_species
```

## Useful Examples

Preview only 5-element systems:

```bash
python generate_element_system_folders.py --dry-run --num-elements 5
```

Create only 5-element systems:

```bash
python generate_element_system_folders.py \
    --output-dir alf_element_systems_n5 \
    --template-dir alf_moltensalt_boilerplate \
    --num-elements 5
```

Create all systems up to 5 elements:

```bash
python generate_element_system_folders.py \
    --output-dir alf_element_systems_max5 \
    --template-dir alf_moltensalt_boilerplate \
    --max-elements 5
```

Create all 3,069 systems:

```bash
python generate_element_system_folders.py \
    --output-dir alf_element_systems_all \
    --template-dir alf_moltensalt_boilerplate
```

## Notes

- Systems are defined by element sets, not by formal salt recipes.
- Element order does not create a new system.
- Every system contains at least one cation and at least one anion.
- `possible_species` is left unchanged unless `--update-hippynn-config` is used.
- The script is intended to support reproducible ALF input generation for large
  Frontier-scale batches.

