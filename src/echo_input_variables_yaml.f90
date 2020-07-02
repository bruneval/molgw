!======================================================================
! The following lines have been generated by a python script: input_variables.py
! Do not alter them directly: they will be overriden sooner or later by the script
! To add a new input variable, modify the script directly
! Generated by input_variables.py on 02 July 2020
!======================================================================

 write(unit_yaml,'(4x,a,15x,es16.8)') 'auto_auxil_fsam:',auto_auxil_fsam 
 write(unit_yaml,'(4x,a,12x,i8)') 'auto_auxil_lmaxinc:',auto_auxil_lmaxinc 
 write(unit_yaml,'(4x,a,19x,a)') 'auxil_basis:',TRIM(auxil_basis) 
 write(unit_yaml,'(4x,a,25x,a)') 'basis:',TRIM(basis) 
 write(unit_yaml,'(4x,a,23x,a)') 'comment:',TRIM(comment) 
 write(unit_yaml,'(4x,a,15x,a)') 'ecp_auxil_basis:',TRIM(ecp_auxil_basis) 
 write(unit_yaml,'(4x,a,21x,a)') 'ecp_basis:',TRIM(ecp_basis) 
 write(unit_yaml,'(4x,a,18x,a)') 'ecp_elements:',TRIM(ecp_elements) 
 write(unit_yaml,'(4x,a,19x,a)') 'ecp_quality:',TRIM(ecp_quality) 
 write(unit_yaml,'(4x,a,22x,a)') 'ecp_type:',TRIM(ecp_type) 
 write(unit_yaml,'(4x,a,17x,a)') 'gaussian_type:',TRIM(gaussian_type) 
 write(unit_yaml,'(4x,a,24x,a)') 'incore:',yesno_to_TrueFalse(incore) 
 write(unit_yaml,'(4x,a,13x,a)') 'memory_evaluation:',yesno_to_TrueFalse(memory_evaluation) 
 write(unit_yaml,'(4x,a,19x,a)') 'move_nuclei:',TRIM(move_nuclei) 
 write(unit_yaml,'(4x,a,25x,i8)') 'nstep:',nstep 
 write(unit_yaml,'(4x,a,27x,a)') 'scf:',TRIM(scf) 
 write(unit_yaml,'(4x,a,22x,es16.8)') 'tolforce:',tolforce 
 write(unit_yaml,'(4x,a,19x,i8)') 'eri3_nbatch:',eri3_nbatch 
 write(unit_yaml,'(4x,a,20x,i8)') 'eri3_npcol:',eri3_npcol 
 write(unit_yaml,'(4x,a,20x,i8)') 'eri3_nprow:',eri3_nprow 
 write(unit_yaml,'(4x,a,19x,es16.8)') 'grid_memory:',grid_memory 
 write(unit_yaml,'(4x,a,15x,i8)') 'mpi_nproc_ortho:',mpi_nproc_ortho 
 write(unit_yaml,'(4x,a,11x,i8)') 'scalapack_block_min:',scalapack_block_min 
 write(unit_yaml,'(4x,a,20x,a)') 'basis_path:',TRIM(basis_path) 
 write(unit_yaml,'(4x,a,15x,a)') 'force_energy_qp:',yesno_to_TrueFalse(force_energy_qp) 
 write(unit_yaml,'(4x,a,13x,a)') 'ignore_bigrestart:',yesno_to_TrueFalse(ignore_bigrestart) 
 write(unit_yaml,'(4x,a,14x,a)') 'print_bigrestart:',yesno_to_TrueFalse(print_bigrestart) 
 write(unit_yaml,'(4x,a,20x,a)') 'print_cube:',yesno_to_TrueFalse(print_cube) 
 write(unit_yaml,'(4x,a,15x,a)') 'print_wfn_files:',yesno_to_TrueFalse(print_wfn_files) 
 write(unit_yaml,'(4x,a,10x,a)') 'print_density_matrix:',yesno_to_TrueFalse(print_density_matrix) 
 write(unit_yaml,'(4x,a,21x,a)') 'print_eri:',yesno_to_TrueFalse(print_eri) 
 write(unit_yaml,'(4x,a,17x,a)') 'print_hartree:',yesno_to_TrueFalse(print_hartree) 
 write(unit_yaml,'(4x,a,15x,a)') 'print_multipole:',yesno_to_TrueFalse(print_multipole) 
 write(unit_yaml,'(4x,a,20x,a)') 'print_pdos:',yesno_to_TrueFalse(print_pdos) 
 write(unit_yaml,'(4x,a,17x,a)') 'print_restart:',yesno_to_TrueFalse(print_restart) 
 write(unit_yaml,'(4x,a,16x,a)') 'print_rho_grid:',yesno_to_TrueFalse(print_rho_grid) 
 write(unit_yaml,'(4x,a,19x,a)') 'print_sigma:',yesno_to_TrueFalse(print_sigma) 
 write(unit_yaml,'(4x,a,7x,a)') 'print_spatial_extension:',yesno_to_TrueFalse(print_spatial_extension) 
 write(unit_yaml,'(4x,a,23x,a)') 'print_w:',yesno_to_TrueFalse(print_w) 
 write(unit_yaml,'(4x,a,21x,a)') 'print_wfn:',yesno_to_TrueFalse(print_wfn) 
 write(unit_yaml,'(4x,a,20x,a)') 'print_yaml:',yesno_to_TrueFalse(print_yaml) 
 write(unit_yaml,'(4x,a,21x,a)') 'read_fchk:',TRIM(read_fchk) 
 write(unit_yaml,'(4x,a,18x,a)') 'read_restart:',yesno_to_TrueFalse(read_restart) 
 write(unit_yaml,'(4x,a,16x,a)') 'calc_dens_disc:',yesno_to_TrueFalse(calc_dens_disc) 
 write(unit_yaml,'(4x,a,17x,a)') 'calc_q_matrix:',yesno_to_TrueFalse(calc_q_matrix) 
 write(unit_yaml,'(4x,a,17x,a)') 'calc_spectrum:',yesno_to_TrueFalse(calc_spectrum) 
 write(unit_yaml,'(4x,a,9x,a)') 'print_cube_diff_tddft:',yesno_to_TrueFalse(print_cube_diff_tddft) 
 write(unit_yaml,'(4x,a,10x,a)') 'print_cube_rho_tddft:',yesno_to_TrueFalse(print_cube_rho_tddft) 
 write(unit_yaml,'(4x,a,15x,a)') 'print_dens_traj:',yesno_to_TrueFalse(print_dens_traj) 
 write(unit_yaml,'(4x,a,4x,a)') 'print_dens_traj_points_set:',yesno_to_TrueFalse(print_dens_traj_points_set) 
 write(unit_yaml,'(4x,a,9x,a)') 'print_dens_traj_tddft:',yesno_to_TrueFalse(print_dens_traj_tddft) 
 write(unit_yaml,'(4x,a,5x,a)') 'print_line_rho_diff_tddft:',yesno_to_TrueFalse(print_line_rho_diff_tddft) 
 write(unit_yaml,'(4x,a,10x,a)') 'print_line_rho_tddft:',yesno_to_TrueFalse(print_line_rho_tddft) 
 write(unit_yaml,'(4x,a,10x,a)') 'print_tddft_matrices:',yesno_to_TrueFalse(print_tddft_matrices) 
 write(unit_yaml,'(4x,a,10x,a)') 'print_mulliken_tddft:',yesno_to_TrueFalse(print_mulliken_tddft) 
 write(unit_yaml,'(4x,a,11x,a)') 'print_tddft_restart:',yesno_to_TrueFalse(print_tddft_restart) 
 write(unit_yaml,'(4x,a,12x,a)') 'read_tddft_restart:',yesno_to_TrueFalse(read_tddft_restart) 
 write(unit_yaml,'(4x,a,20x,es16.8)') 'write_step:',write_step 
 write(unit_yaml,'(4x,a,17x,es16.8)') 'mulliken_step:',mulliken_step 
 write(unit_yaml,'(4x,a,10x,a)') 'assume_scf_converged:',yesno_to_TrueFalse(assume_scf_converged) 
 write(unit_yaml,'(4x,a,12x,a)') 'ci_greens_function:',TRIM(ci_greens_function) 
 write(unit_yaml,'(4x,a,21x,i8)') 'ci_nstate:',ci_nstate 
 write(unit_yaml,'(4x,a,16x,i8)') 'ci_nstate_self:',ci_nstate_self 
 write(unit_yaml,'(4x,a,10x,i8)') 'ci_spin_multiplicity:',ci_spin_multiplicity 
 write(unit_yaml,'(4x,a,23x,a)') 'ci_type:',TRIM(ci_type) 
 write(unit_yaml,'(4x,a,22x,i8)') 'dft_core:',dft_core 
 write(unit_yaml,'(4x,a,15x,a)') 'ecp_small_basis:',TRIM(ecp_small_basis) 
 write(unit_yaml,'(4x,a,27x,es16.8)') 'eta:',eta 
 write(unit_yaml,'(4x,a,20x,a)') 'frozencore:',yesno_to_TrueFalse(frozencore) 
 write(unit_yaml,'(4x,a,17x,a)') 'gwgamma_tddft:',yesno_to_TrueFalse(gwgamma_tddft) 
 write(unit_yaml,'(4x,a,24x,i8)') 'ncoreg:',ncoreg 
 write(unit_yaml,'(4x,a,24x,i8)') 'ncorew:',ncorew 
 write(unit_yaml,'(4x,a,19x,i8)') 'nexcitation:',nexcitation 
 write(unit_yaml,'(4x,a,19x,i8)') 'nomega_imag:',nomega_imag 
 write(unit_yaml,'(4x,a,18x,i8)') 'nomega_sigma:',nomega_sigma 
 write(unit_yaml,'(4x,a,21x,i8)') 'nstep_dav:',nstep_dav 
 write(unit_yaml,'(4x,a,22x,i8)') 'nstep_gw:',nstep_gw 
 write(unit_yaml,'(4x,a,21x,i8)') 'nvirtualg:',nvirtualg 
 write(unit_yaml,'(4x,a,21x,i8)') 'nvirtualw:',nvirtualw 
 write(unit_yaml,'(4x,a,23x,a)') 'postscf:',TRIM(postscf) 
 write(unit_yaml,'(4x,a,10x,a)') 'postscf_diago_flavor:',TRIM(postscf_diago_flavor) 
 write(unit_yaml,'(4x,a,16x,a)') 'pt3_a_diagrams:',TRIM(pt3_a_diagrams) 
 write(unit_yaml,'(4x,a,13x,a)') 'pt_density_matrix:',TRIM(pt_density_matrix) 
 write(unit_yaml,'(4x,a,21x,es16.8)') 'rcut_mbpt:',rcut_mbpt 
 write(unit_yaml,'(4x,a,23x,es16.8)') 'scissor:',scissor 
 write(unit_yaml,'(4x,a,10x,i8)') 'selfenergy_state_max:',selfenergy_state_max 
 write(unit_yaml,'(4x,a,10x,i8)') 'selfenergy_state_min:',selfenergy_state_min 
 write(unit_yaml,'(4x,a,8x,i8)') 'selfenergy_state_range:',selfenergy_state_range 
 write(unit_yaml,'(4x,a,19x,a)') 'small_basis:',TRIM(small_basis) 
 write(unit_yaml,'(4x,a,20x,es16.8)') 'step_sigma:',step_sigma 
 write(unit_yaml,'(4x,a,22x,a)') 'stopping:',yesno_to_TrueFalse(stopping) 
 write(unit_yaml,'(4x,a,27x,a)') 'tda:',yesno_to_TrueFalse(tda) 
 write(unit_yaml,'(4x,a,12x,a)') 'tddft_grid_quality:',TRIM(tddft_grid_quality) 
 write(unit_yaml,'(4x,a,24x,es16.8)') 'toldav:',toldav 
 write(unit_yaml,'(4x,a,23x,a)') 'triplet:',yesno_to_TrueFalse(triplet) 
 write(unit_yaml,'(4x,a,1x,a)') 'use_correlated_density_matrix:',yesno_to_TrueFalse(use_correlated_density_matrix) 
 write(unit_yaml,'(4x,a,19x,a)') 'virtual_fno:',yesno_to_TrueFalse(virtual_fno) 
 write(unit_yaml,'(4x,a,21x,"[",es16.8,", ",es16.8,", ",es16.8,"]")') 'excit_dir:',excit_dir 
 write(unit_yaml,'(4x,a,19x,es16.8)') 'excit_kappa:',excit_kappa 
 write(unit_yaml,'(4x,a,20x,a)') 'excit_name:',TRIM(excit_name) 
 write(unit_yaml,'(4x,a,19x,es16.8)') 'excit_omega:',excit_omega 
 write(unit_yaml,'(4x,a,19x,es16.8)') 'excit_time0:',excit_time0 
 write(unit_yaml,'(4x,a,24x,i8)') 'n_hist:',n_hist 
 write(unit_yaml,'(4x,a,24x,i8)') 'n_iter:',n_iter 
 write(unit_yaml,'(4x,a,15x,i8)') 'n_restart_tddft:',n_restart_tddft 
 write(unit_yaml,'(4x,a,19x,i8)') 'ncore_tddft:',ncore_tddft 
 write(unit_yaml,'(4x,a,21x,a)') 'pred_corr:',TRIM(pred_corr) 
 write(unit_yaml,'(4x,a,21x,a)') 'prop_type:',TRIM(prop_type) 
 write(unit_yaml,'(4x,a,5x,es16.8)') 'projectile_charge_scaling:',projectile_charge_scaling 
 write(unit_yaml,'(4x,a,24x,es16.8)') 'r_disc:',r_disc 
 write(unit_yaml,'(4x,a,14x,a)') 'tddft_frozencore:',yesno_to_TrueFalse(tddft_frozencore) 
 write(unit_yaml,'(4x,a,22x,es16.8)') 'time_sim:',time_sim 
 write(unit_yaml,'(4x,a,21x,es16.8)') 'time_step:',time_step 
 write(unit_yaml,'(4x,a,16x,"[",es16.8,", ",es16.8,", ",es16.8,"]")') 'vel_projectile:',vel_projectile 
 write(unit_yaml,'(4x,a,18x,es16.8)') 'alpha_hybrid:',alpha_hybrid 
 write(unit_yaml,'(4x,a,18x,es16.8)') 'alpha_mixing:',alpha_mixing 
 write(unit_yaml,'(4x,a,19x,es16.8)') 'beta_hybrid:',beta_hybrid 
 write(unit_yaml,'(4x,a,8x,es16.8)') 'density_matrix_damping:',density_matrix_damping 
 write(unit_yaml,'(4x,a,19x,es16.8)') 'diis_switch:',diis_switch 
 write(unit_yaml,'(4x,a,18x,es16.8)') 'gamma_hybrid:',gamma_hybrid 
 write(unit_yaml,'(4x,a,18x,a)') 'grid_quality:',TRIM(grid_quality) 
 write(unit_yaml,'(4x,a,14x,a)') 'init_hamiltonian:',TRIM(init_hamiltonian) 
 write(unit_yaml,'(4x,a,14x,a)') 'integral_quality:',TRIM(integral_quality) 
 write(unit_yaml,'(4x,a,21x,es16.8)') 'kerker_k0:',kerker_k0 
 write(unit_yaml,'(4x,a,9x,es16.8)') 'level_shifting_energy:',level_shifting_energy 
 write(unit_yaml,'(4x,a,19x,es16.8)') 'min_overlap:',min_overlap 
 write(unit_yaml,'(4x,a,17x,a)') 'mixing_scheme:',TRIM(mixing_scheme) 
 write(unit_yaml,'(4x,a,19x,i8)') 'npulay_hist:',npulay_hist 
 write(unit_yaml,'(4x,a,26x,i8)') 'nscf:',nscf 
 write(unit_yaml,'(4x,a,14x,a)') 'partition_scheme:',TRIM(partition_scheme) 
 write(unit_yaml,'(4x,a,14x,a)') 'scf_diago_flavor:',TRIM(scf_diago_flavor) 
 write(unit_yaml,'(4x,a,24x,es16.8)') 'tolscf:',tolscf 
 write(unit_yaml,'(4x,a,24x,es16.8)') 'charge:',charge 
 write(unit_yaml,'(4x,a,19x,a)') 'length_unit:',TRIM(length_unit) 
 write(unit_yaml,'(4x,a,17x,es16.8)') 'magnetization:',magnetization 
 write(unit_yaml,'(4x,a,25x,i8)') 'natom:',natom 
 write(unit_yaml,'(4x,a,24x,i8)') 'nghost:',nghost 
 write(unit_yaml,'(4x,a,25x,i8)') 'nspin:',nspin 
 write(unit_yaml,'(4x,a,19x,es16.8)') 'temperature:',temperature 
 write(unit_yaml,'(4x,a,22x,a)') 'xyz_file:',TRIM(xyz_file) 


!======================================================================
