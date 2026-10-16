# Testing the USalt Demo

The example is in the [`examples/USalt`](https://github.com/messerlyra/CAAR-Discovery/tree/USalt_prep/examples/USalt) directory of the `USalt_prep` branch.

## Setup

Starting a `tmux` session is optional but recommended:

```bash
tmux new
```

Activate the CAAR environment:

```bash
source /lustre/orion/world-shared/csc728/messerlyra/scripts/load_caar_env.bash
```

Change to the demo system directory:

```bash
cd CAAR-Discovery/examples/USalt/demo_USalt/system_000001_n14_c-Li-Na-K-Rb-Cs-Be-Mg-Ca-Sr-Ba-Zn-Zr_a-F-Cl
```

## Run the Tests

Run the builder test:

```bash
python -m alframework --master master_config.json --test_builder
```

Run the molecular-dynamics (MD) test:

```bash
python -m alframework --master master_md.json
```

Optionally, add `--test_sampler` to test the sampler:

```bash
python -m alframework --master master_md.json --test_sampler
```

Run the quantum-mechanics (QM) test:

```bash
python -m alframework --master master_qm.json
```

Optionally, add `--test_qm` to test QM:

```bash
python -m alframework --master master_qm.json --test_qm
```

Run the machine-learning (ML) test:

```bash
python -m alframework --master master_ml.json
```

Optionally, add `--test_ml` to test ML:

```bash
python -m alframework --master master_ml.json --test_ml
```

