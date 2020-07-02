-----------------------------------------
#                 MOLGW
-----------------------------------------


Many-body perturbation theory for atoms, molecules, and clusters


## Getting started

This is a minimalistic README file.
Many more details can be found ~/docs/molgw_manual.html
or on the web site [molgw.org](http://www.molgw.org/start.html)


## Features

MOLGW implements the following schemes:
- Hartree-Fock
- LDA (PW, VWN)
- GGA (PBE, PW91, BLYP)
- potential-only meta-GGA (BJ, RPP)
- hybrid functionals (PBE0, B3LYP)
- screened hybrid functionals (HSE03, HSE06)
- HF+GW
- DFT+GW
- Hybrid+GW
- QPscGW
- HF+MP2
- DFT+MP2
- Hybrid+MP2
- QPscMP2
- CI for 2 electrons 
- TD-HF
- TD-DFT
- BSE


## Installation

MOLGW needs Fortran 2003 and C++ compilers.
The machine dependent variables should be set in file `~molgw/src/my_machine.arch`
Examples for this file can be found in the folder `~molgw/config/`.
Then
`cd ~molgw/src`
`make`

- BLAS and LAPACK linear algebra libraries are required.
- libint is required: (version 2.2.x or newer)
https://github.com/evaleev/libint/releases
- libxc is required: (version >= 3.0.0) for DFT calculations
http://www.tddft.org/programs/octopus/down.php?file=libxc/libxc-3.0.0.tar.gz


## Basis sets
More basis sets can be obtained from [Basis Set Exchange](https://bse.pnl.gov/bse/portal)
The file can be generated from a NWChem file using the script
`~molgw/utils/basis_nwchem2molgw.py B_aug-cc-pVDZ.nwchem`


## Usage

`./molgw helium.in > helium.out`

Example input files can be found in `~molgw/tests/`


## Known issues
- QPscGW scf loop might be quite unstable for large basis sets, use a large eta
- TD-DFT GGA kernel can induce very large numerical values which limits the numerical stability and breaks some comparison with other codes.
Especially when compiling with gfortran/gcc. ifort/icc behaves much better.


## Information for developers

Besides the calls to the libint library, MOLGW is entirely written in Fortran2003/2008.
The source files can be found in src/.

### Coding Rules
The Fortran intent in/out/inout is compulsory for the arguments of a subroutine.
One character variable names are discouraged.

The careful developer should try
- to follow the overall layout and the conventions of the code (double space indent, separation of the list of variables arguments/local, loop counters naming, etc.)
- to protect the data contained in a module with private or protected attribute as much as possible.
- to avoid cascading object access, such as a%b%c (Create methods instead)
- to hide the MPI statements with a generic wrapper in subroutine src/m_mpi.f90.
- to hide the SCALAPACK statements with a generic wrapper in subroutine src/m_scalapack.f90 (not implemented as of today).

### Automatically generated files
A few fortran source files are generated by python scripts:
- src/basis_path.f90
- src/revision.f90 
are generated by src/prepare_sourcecode.py (that is run at each "make" operation)
and
- src/input_variables.f90
is generated by utils/input_variables.py from a YAML file src/input_variables.yaml .
Do not attempt to edit the fortran files. You should rather edit the yaml file.

To add a new input variable, append a new variable description in the YAML file src/input_variables.yaml.
Then execute the python script utils/input_variables.py.
This will generate automatically the Fortran source file src/input_variables.f90
and the HTML documentation file docs/input_variables.html.

### Adding a new source file
It requires the manual editing of the src/Makefile.
Please check carefully the dependence so to compile and add it to the right "level" of the Makefile.
The code should compile properly in parallel with "make -j".


## Main author

Fabien Bruneval

Service de Recherches de Métallurgie Physique
CEA Saclay, F-91191 Gif-sur-Yvette, France
