import pytest
import sys
import os

# Add demo directory to path to import custom_builders and tools
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'demo'))

from custom_builders import atomic_system_task
from tools import run_parsl
from alframework.tools.molecules_class import MoleculesObject

def test_atomic_system_task():
    # Mock configuration based on builder_config.json
    atom_charges = {
        "Li": 1,
        "F": -1
    }
    target_num_atoms = 6
    min_distance = 1.0
    density_range = [0.1, 0.5]
    moleculeid = "test_mol_1"

    # Run the builder task
    molecule_object = run_parsl(
        atomic_system_task,
        moleculeid=moleculeid,
        atom_charges=atom_charges,
        target_num_atoms=target_num_atoms,
        min_distance=min_distance,
        density_range=density_range
    )

    # Assertions
    assert isinstance(molecule_object, MoleculesObject)
    assert molecule_object.get_moleculeid() == moleculeid
    atoms = molecule_object.get_atoms()
    assert atoms is not None
    assert len(atoms) == target_num_atoms
    # Check that only specified elements are present
    symbols = atoms.get_chemical_symbols()
    assert all(s in atom_charges for s in symbols)

if __name__ == "__main__":
    pytest.main([__file__])
