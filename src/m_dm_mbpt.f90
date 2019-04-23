!=========================================================================
! This file is part of MOLGW.
! Author: Fabien Bruneval
!
! This module contains
! the reading or the calculation of correlated density matrix
!
!=========================================================================
module m_dm_mbpt
 use m_definitions
 use m_timing
 use m_warning
 use m_memory
 use m_inputparam
 use m_spectral_function
 use m_selfenergy_tools
 use m_scf
 use m_hamiltonian
 use m_hamiltonian_wrapper


contains


!=========================================================================
subroutine get_dm_mbpt(basis,occupation,energy,c_matrix, &
                             hamiltonian_kinetic,hamiltonian_nucleus,hamiltonian_hartree,hamiltonian_exx,hamiltonian_xc)
 implicit none

 type(basis_set),intent(in)      :: basis
 real(dp),intent(in)             :: occupation(:,:)
 real(dp),intent(in)             :: energy(:,:)
 real(dp),intent(in)             :: c_matrix(:,:,:)
 real(dp),intent(in)             :: hamiltonian_kinetic(:,:)
 real(dp),intent(in)             :: hamiltonian_nucleus(:,:)
 real(dp),intent(in)             :: hamiltonian_hartree(:,:)
 real(dp),intent(inout)          :: hamiltonian_exx(:,:,:)
 real(dp),intent(inout)          :: hamiltonian_xc(:,:,:)
!=====
 integer                    :: nstate
 logical                    :: density_matrix_found
 integer                    :: file_density_matrix
 integer                    :: ispin,istate
 type(spectral_function)    :: wpol
 type(energy_contributions) :: en_dm_corr
 real(dp)                   :: en_rpa
 real(dp),allocatable       :: hartree_ii(:,:),exchange_ii(:,:)
 real(dp),allocatable       :: p_matrix_corr(:,:,:)
 real(dp),allocatable       :: hamiltonian_hartree_corr(:,:)
 real(dp),allocatable       :: hamiltonian_exx_corr(:,:,:)
 real(dp),allocatable       :: c_matrix_tmp(:,:,:)
 real(dp),allocatable       :: occupation_tmp(:,:)
!=====

 nstate = SIZE(c_matrix,DIM=2)

 call clean_allocate('Correlated density matrix',p_matrix_corr,basis%nbf,basis%nbf,nspin)
 call clean_allocate('Correlated Hartree potential',hamiltonian_hartree_corr,basis%nbf,basis%nbf)
 call clean_allocate('Correlated exchange operator',hamiltonian_exx_corr,basis%nbf,basis%nbf,nspin)
 p_matrix_corr(:,:,:) = 0.0_dp

 !
 ! Three possibilities: read_fchk , pt_density_matrix, DENSITY_MATRIX
 !

 ! Option 1:
 ! Is there a Gaussian formatted checkpoint file to be read?
 if( read_fchk /= 'NO') call read_gaussian_fchk(read_fchk,'gaussian.fchk',basis,p_matrix_corr)

 ! Option 2:
 ! Calculate a MBPT density matrix if requested
 select case(TRIM(pt_density_matrix))
 case('ONE-RING')
   ! This keyword calculates the 1-ring density matrix as it is derived in PT2 theory
   call selfenergy_set_state_range(nstate,occupation)
   call fock_density_matrix(nstate,basis,occupation,energy,c_matrix,hamiltonian_exx,hamiltonian_xc,p_matrix_corr)
   call onering_density_matrix(nstate,basis,occupation,energy,c_matrix,p_matrix_corr)
 case('PT2')
   ! This keyword calculates the PT2 density matrix as it is derived in PT2 theory (differs from MP2 density matrix)
   call selfenergy_set_state_range(nstate,occupation)
   call fock_density_matrix(nstate,basis,occupation,energy,c_matrix,hamiltonian_exx,hamiltonian_xc,p_matrix_corr)
   call pt2_density_matrix(nstate,basis,occupation,energy,c_matrix,p_matrix_corr)
 case('GW','G0W0')
   ! This keyword calculates the GW density matrix as it is derived in the new GW theory
   call init_spectral_function(nstate,occupation,0,wpol)
   call polarizability(.TRUE.,.TRUE.,basis,nstate,occupation,energy,c_matrix,en_rpa,wpol)
   call selfenergy_set_state_range(nstate,occupation)
   call fock_density_matrix(nstate,basis,occupation,energy,c_matrix,hamiltonian_exx,hamiltonian_xc,p_matrix_corr)
   call gw_density_matrix(nstate,basis,occupation,energy,c_matrix,wpol,p_matrix_corr)
   call destroy_spectral_function(wpol)
 case('GW_IMAGINARY','G0W0_IMAGINARY')
   ! This keyword calculates the GW density matrix as it is derived in the new GW theory
   ! using an imaginary axis integral
   call init_spectral_function(nstate,occupation,nomega_imag,wpol)
   call polarizability_grid_scalapack(basis,nstate,occupation,energy,c_matrix,en_rpa,wpol)
   call selfenergy_set_state_range(nstate,occupation)
   call fock_density_matrix(nstate,basis,occupation,energy,c_matrix,hamiltonian_exx,hamiltonian_xc,p_matrix_corr)
   call gw_density_matrix_imag(nstate,basis,occupation,energy,c_matrix,wpol,p_matrix_corr)
   call destroy_spectral_function(wpol)
 case('GW_DYSON','G0W0_DYSON')
   ! This keyword calculates the GW density matrix as it is derived in the new GW theory
   ! using an imaginary axis integral
   call init_spectral_function(nstate,occupation,nomega_imag,wpol)
   call polarizability_grid_scalapack(basis,nstate,occupation,energy,c_matrix,en_rpa,wpol)
   call selfenergy_set_state_range(nstate,occupation)
   call fock_density_matrix(nstate,basis,occupation,energy,c_matrix,hamiltonian_exx,hamiltonian_xc,p_matrix_corr)
   call gw_density_matrix_dyson_imag(nstate,basis,occupation,energy,c_matrix,wpol,p_matrix_corr)
   call destroy_spectral_function(wpol)
 end select


 ! Option 3:
 ! If no p_matrix_corr is present yet, then try to read it from a DENSITY_MATRIX file
 if( ALL( ABS(p_matrix_corr(:,:,:)) < 0.01_dp ) ) then
   inquire(file='DENSITY_MATRIX',exist=density_matrix_found)
   if( density_matrix_found) then
     write(stdout,'(/,1x,a)') 'Reading a MOLGW density matrix file: DENSITY_MATRIX'
     open(newunit=file_density_matrix,file='DENSITY_MATRIX',form='unformatted',action='read')
     do ispin=1,nspin
       read(file_density_matrix) p_matrix_corr(:,:,ispin)
     enddo
     close(file_density_matrix)
   else
     call die('m_scf_loop: no correlated density matrix read or calculated though input file suggests you really want one')
   endif

 endif

 if( print_hartree_ .OR. use_correlated_density_matrix_ ) then

   en_dm_corr%nuc_nuc = en%nuc_nuc
   en_dm_corr%kin = SUM( hamiltonian_kinetic(:,:) * SUM(p_matrix_corr(:,:,:),DIM=3) )
   en_dm_corr%nuc = SUM( hamiltonian_nucleus(:,:) * SUM(p_matrix_corr(:,:,:),DIM=3) )

   call calculate_hartree(basis,p_matrix_corr,hamiltonian_hartree_corr,eh=en_dm_corr%hart)

   call calculate_exchange(basis,p_matrix_corr,hamiltonian_exx_corr,ex=en_dm_corr%exx)

   en_dm_corr%tot = en_dm_corr%nuc_nuc + en_dm_corr%kin + en_dm_corr%nuc +  en_dm_corr%hart + en_dm_corr%exx
   write(stdout,'(/,1x,a)') 'Energies from correlated density matrix'
   write(stdout,'(a25,1x,f19.10)')   'Kinetic Energy (Ha):',en_dm_corr%kin
   write(stdout,'(a25,1x,f19.10)')   'Nucleus Energy (Ha):',en_dm_corr%nuc
   write(stdout,'(a25,1x,f19.10)')   'Hartree Energy (Ha):',en_dm_corr%hart
   write(stdout,'(a25,1x,f19.10)')  'Exchange Energy (Ha):',en_dm_corr%exx
   write(stdout,'(a25,1x,f19.10)') 'Total EXX Energy (Ha):',en_dm_corr%tot

   allocate(hartree_ii(nstate,nspin),exchange_ii(nstate,nspin))
   do ispin=1,nspin
     do istate=1,nstate
        hartree_ii(istate,ispin)  =  DOT_PRODUCT( c_matrix(:,istate,ispin) , &
                                                  MATMUL( hamiltonian_hartree_corr(:,:) , c_matrix(:,istate,ispin) ) )
        exchange_ii(istate,ispin) =  DOT_PRODUCT( c_matrix(:,istate,ispin) , &
                                                  MATMUL( hamiltonian_exx_corr(:,:,ispin) , c_matrix(:,istate,ispin) ) )
     enddo
   enddo
   call dump_out_energy('=== Hartree expectation value from correlated density matrix ===',nstate,nspin,occupation,hartree_ii)
   call dump_out_energy('=== Exchange expectation value from correlated density matrix ===',nstate,nspin,occupation,exchange_ii)
   deallocate(hartree_ii,exchange_ii)
 endif

 if( print_multipole_ .OR. print_cube_ ) then
   allocate(c_matrix_tmp(basis%nbf,basis%nbf,nspin))
   allocate(occupation_tmp(basis%nbf,nspin))
   call get_c_matrix_from_p_matrix(p_matrix_corr,c_matrix_tmp,occupation_tmp)
   if( print_multipole_ ) then
     call static_dipole(basis%nbf,basis,occupation_tmp,c_matrix_tmp)
     call static_quadrupole(basis%nbf,basis,occupation_tmp,c_matrix_tmp)
   endif
   if( print_cube_ ) then
     call plot_cube_wfn('MBPT',basis%nbf,basis,occupation_tmp,c_matrix_tmp)
   endif
   deallocate(c_matrix_tmp)
   deallocate(occupation_tmp)
 endif

 if( use_correlated_density_matrix_ ) then
   !
   ! Since the density matrix p_matrix is updated,
   ! one needs to recalculate the hartree and the exchange potentials
   ! let us include the old hartree in hamiltonian_xc and the new one in hamiltonian_exchange
   do ispin=1,nspin
     hamiltonian_xc(:,:,ispin)  = hamiltonian_xc(:,:,ispin) + hamiltonian_hartree(:,:)
     hamiltonian_exx(:,:,ispin) = hamiltonian_exx_corr(:,:,ispin) + hamiltonian_hartree_corr(:,:)
   enddo

 endif

 write(stdout,*)
 call clean_deallocate('Correlated density matrix',p_matrix_corr)
 call clean_deallocate('Correlated Hartree potential',hamiltonian_hartree_corr)
 call clean_deallocate('Correlated exchange operator',hamiltonian_exx_corr)


end subroutine get_dm_mbpt


!=========================================================================
end module m_dm_mbpt
!=========================================================================
