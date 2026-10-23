import sys
import os

import pytest
import h5py
import numpy as np
from ase import Atoms
from alframework.tools.molecules_class import MoleculesObject

# Add demo directory to path to import custom_builders and tools
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'demo'))

from tools import load_molecules_from_h5

def test_load_molecules_from_h5(tmpdir):
    # Create a dummy HDF5 file for testing
    test_h5 = tmpdir/'test_molecules.h5'
        
    with h5py.File(test_h5, 'w') as f:
        group = f.create_group('group1')
        mol_group = group.create_group('mol1')
        mol_group.create_dataset('cell', data=np.eye(3).reshape((1,3,3))*10)
        mol_group.create_dataset('coordinates', data=np.zeros((1,2,3)))
        mol_group.create_dataset('species', data=[b'H', b'H'])

    try:
        mols = load_molecules_from_h5(test_h5)
        assert len(mols) == 1
        assert mols[0].get_moleculeid() == '0'
        assert len(mols[0].get_atoms()) == 2
    finally:
        import os
        if os.path.exists(test_h5):
            os.remove(test_h5)

if __name__ == "__main__":
    pytest.main([__file__])
