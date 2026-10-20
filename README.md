# ALF FOM Measurement Setup for CAAR

The `demo/run_*.py` scripts execute the three parts of
the FOM individually on test structures and hippynn parameters from:

- `demo/h5store/data-Li_Na_K_Rb_Cs_Be_Mg_Ca_Sr_Ba_F_Cl-0000.h5`
- `demo/ensembles/ensemble-0000/model-*/best_model.pt`

The run-scripts work around parsl using `tools.run_parsl`, a helper
which executes `parsl.python_app`-decorated functions directly.
Note that this direct-run method will have different overhead costs
than running within parsl, since parsl starts up each worker once
and passes input/output pairs via network messages.

It is thus suitable for measuring and testing components only.
The full, initial FOM measurement requires using parsl, since that
is ALF's workflow engine.

## Installation

This workflow depends on the following python packages:

- https://github.com/bnebgen-LANL/ase.git
- https://github.com/messerlyra/ALF-CAAR.git
- https://github.com/messerlyra/hippynn-CAAR.git
- rootstock

The `build_scripts` directory documents
a working environment setup on Frontier.

## Tests

The tests/ directory records simple tests of the helper
functions in `demo/tools.py`.

## Run Example


