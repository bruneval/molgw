!=========================================================================
! This file is part of MOLGW.
! Author: Fabien Bruneval
!
! This file contains
! the driver for the different self-energy methods:
! PT2, PT3, GW, evGW, COHSEX, GWGamma, etc.
!
!=========================================================================
subroutine selfenergy_evaluation(basis,auxil_basis,nstate,occupation,energy,c_matrix, &
                                 exchange_m_vxc_diag)
 use m_definitions
 use m_timing
 use m_warning
 use m_memory
 use m_inputparam
 use m_eri
 use m_eri_calculate
 use m_eri_ao_mo
 use m_dft_grid
 use m_scf,only: en
 use m_hamiltonian
 use m_spectral_function
 use m_selfenergy_tools
 use m_virtual_orbital_space
 implicit none

 type(basis_set),intent(in) :: basis
 type(basis_set),intent(in) :: auxil_basis
 integer,intent(in)         :: nstate
 real(dp),intent(in)        :: occupation(nstate,nspin)
 real(dp),intent(inout)     :: energy(nstate,nspin)
 real(dp),intent(inout)     :: c_matrix(basis%nbf,nstate,nspin)
 real(dp),intent(in)        :: exchange_m_vxc_diag(nstate,nspin)
!=====
 type(selfenergy_grid)   :: se,se2,se3,se_sox,se_gwpt3
 logical                 :: enforce_rpa
 character(len=36)       :: selfenergy_tag
 integer                 :: reading_status
 integer                 :: nstate_small
 type(spectral_function) :: wpol
 real(dp),allocatable    :: matrix_tmp(:,:,:)
 real(dp),allocatable    :: sigc(:,:)
 real(dp)                :: energy_g(nstate,nspin)
 real(dp)                :: energy_w(nstate,nspin)
 real(dp),allocatable    :: zz(:,:)
 real(dp),allocatable    :: energy_qp_new(:,:),energy_qp_z(:,:)
 integer                 :: iomega
 integer                 :: istep_gw
#ifdef COHSEX_DEVEL
 integer,parameter       :: BATCH_SIZE = 128
 type(calculation_type)  :: calc_type_tmp
 real(dp),allocatable    :: p_matrix(:,:,:)
 integer                 :: istate
 real(dp)                :: exc
 integer                 :: ispin
#endif
!=====

 write(stdout,'(/,/,1x,a)') '=================================================='
 write(stdout,'(1x,a)')     'Self-energy evaluation starts here'
 write(stdout,'(1x,a,/)')   '=================================================='

 !
 ! Small imaginary part of the poles in the Green's function
 ! output here
 write(msg,'(es9.2)') AIMAG(ieta)
 call issue_warning('small complex number is '//msg)


 do istep_gw=1,nstep_gw

   !
   ! Set the character string for the calculation we are currently doing
   select case(calc_type%selfenergy_approx)
   case(GW,G0W0_IOMEGA)
     selfenergy_tag='GW'
   case(GnW0)
     write(selfenergy_tag,'(i3)') istep_gw-1
     selfenergy_tag='G'//TRIM(ADJUSTL(selfenergy_tag))//'W0'
   case(GnWn)
     write(selfenergy_tag,'(i3)') istep_gw-1
     selfenergy_tag='G'//TRIM(ADJUSTL(selfenergy_tag))//'W'//TRIM(ADJUSTL(selfenergy_tag))
   case(PT2)
     if( calc_type%selfenergy_static ) then
       selfenergy_tag='PT1PT2'
     else
       selfenergy_tag='PT2'
     endif
   case(TWO_RINGS)
     selfenergy_tag='TWO_RINGS'
   case(PT3)
     selfenergy_tag='PT3'
   case(ONE_RING)
     selfenergy_tag='ONE_RING'
   case(SOX)
     selfenergy_tag='SOX'
   case(G0W0SOX0)
     selfenergy_tag='GWSOX'
   case(GWSOX)
     selfenergy_tag='GWSOX'
   case(GWPT3)
     selfenergy_tag='GWPT3'
   case(G0W0Gamma0)
     selfenergy_tag='GWGamma'
   case(COHSEX,COHSEX_DEVEL,TUNED_COHSEX)
     selfenergy_tag='COHSEX'
   case default
     write(stdout,*) 'selfenergy approx not listed:',calc_type%selfenergy_approx
     call die('selfenergy_evaluation: bug')
   end select


   !
   ! Set the range of states on which to evaluate the self-energy
   call selfenergy_set_state_range(nstate,occupation)

   !
   ! If requested,
   ! prepare an optmized virtual subspace based on
   ! Frozen Natural Orbitals technique
   if( is_virtual_fno ) then
     !
     ! Be aware that the energies and the c_matrix for virtual orbitals are altered after this point
     ! and until they are restored in destroy_fno
     !
     call virtual_fno(basis,nstate,nsemax,occupation,energy,c_matrix)
   endif
   !
   ! Or alternatively use the small basis technique
   if( has_small_basis ) then
     if( scalapack_nprow == 1 .AND. scalapack_npcol == 1 ) then
       call setup_virtual_smallbasis(basis,nstate,occupation,nsemax,energy,c_matrix,nstate_small)
     else
       call setup_virtual_smallbasis_sca(basis,nstate,occupation,nsemax,energy,c_matrix,nstate_small)
     endif
     !
     ! Set the range again after the change of the virtual space
     ! to nstate
     call selfenergy_set_state_range(nstate_small,occupation)
   else
     nstate_small = nstate
   endif




   !
   ! Choose which one-electron energies to use in G and in W
   !
   if( calc_type%selfenergy_technique == EVSC .OR. force_energy_qp_ ) then
     call read_energy_qp(nstate,energy_g,reading_status)
     if(reading_status/=0) then
       call issue_warning('File energy_qp not found: assuming 1st iteration')
       energy_g(:,:) = energy(:,:)
     endif

     !
     ! For GnWn, update both the energy in G and in W
     if( calc_type%selfenergy_approx == GnWn ) then
       energy_w(:,:) = energy_g(:,:)
     else
       energy_w(:,:) = energy(:,:)
     endif

   else
     energy_g(:,:) = energy(:,:)
     energy_w(:,:) = energy(:,:)
   endif


   call init_selfenergy_grid(calc_type%selfenergy_technique,energy_g,se)



   !
   ! selfenergy = GW or COHSEX
   !
   if(     calc_type%selfenergy_approx == GV .OR. calc_type%selfenergy_approx == GSIGMA .OR.  calc_type%selfenergy_approx == LW &
      .OR. calc_type%selfenergy_approx == LW2 &
      .OR. calc_type%selfenergy_approx == G0W0_IOMEGA &
      .OR. calc_type%selfenergy_approx == GW   .OR. calc_type%selfenergy_approx == COHSEX   &
      .OR. calc_type%selfenergy_approx == GnW0 .OR. calc_type%selfenergy_approx == GnWn   ) then

     !
     ! First calculate W except if performing GnW0 for the second and following times
     !
     if( calc_type%selfenergy_approx == GnW0 .AND. istep_gw > 1 ) then
       write(stdout,'(/,1x,a,/)') 'GnW0 calculations skip the re-calculation of W'
     else

       call init_spectral_function(nstate_small,occupation,nomega_imag,wpol)

       ! Try to read a spectral function file in order to skip the polarizability calculation
       ! Skip the reading if GnWn (=evGW) is requested
       if( calc_type%selfenergy_approx /= GnWn ) then
         call read_spectral_function(wpol,reading_status)
       else
         write(stdout,'(/,1x,a)') 'For GnWn calculations, never try to read file SCREENED_COULOMB'
         reading_status = 1
       endif
       ! If reading has failed, then do the calculation
       if( reading_status /= 0 ) then
         if( calc_type%selfenergy_technique /= imaginary_axis ) then
           ! in case of BSE calculation, enforce RPA here
           enforce_rpa = calc_type%is_bse
           call polarizability(enforce_rpa,.TRUE.,basis,nstate,occupation,energy_w,c_matrix,en%rpa,wpol)
         else
           call polarizability_grid_scalapack(basis,nstate,occupation,energy_w,c_matrix,en%rpa,wpol)
         endif
       endif

       en%tot = en%tot + en%rpa
       if( calc_type%is_dft ) en%tot = en%tot - en%xc - en%exx_hyb + en%exx
       if( ABS(en%rpa) > 1.e-6_dp) then
         write(stdout,'(/,a,f19.10)') ' RPA Total energy (Ha): ',en%tot
       endif

     endif

#ifdef HAVE_SCALAPACK
     ! The SCALAPACK implementation only works for plain vanilla GW
     ! TODO: extend it to COHSEX
     if( has_auxil_basis &
       .AND. (calc_type%selfenergy_approx == GW .OR. calc_type%selfenergy_approx == GnW0  &
         .OR. calc_type%selfenergy_approx == GnWn .OR. calc_type%selfenergy_approx == G0W0_IOMEGA) ) then
       if( calc_type%selfenergy_technique /= imaginary_axis ) then
         call gw_selfenergy_scalapack(calc_type%selfenergy_approx,nstate,basis,occupation,energy_g,c_matrix,wpol,se)
       else
         call gw_selfenergy_imag_scalapack(basis,nstate,energy_g,c_matrix,wpol,se)
         call self_energy_pade(se)
       endif
     else
       call gw_selfenergy(calc_type%selfenergy_approx,nstate,basis,occupation,energy_g,c_matrix,wpol,se,en%gw)
     endif
#else
     if( calc_type%selfenergy_technique /= imaginary_axis ) then
       call gw_selfenergy(calc_type%selfenergy_approx,nstate,basis,occupation,energy_g,c_matrix,wpol,se,en%gw)
     else
       call gw_selfenergy_imag_scalapack(basis,nstate,energy_g,c_matrix,wpol,se)
       call self_energy_pade(se)
     endif
#endif



     if( ABS(en%gw) > 1.0e-5_dp ) then
       write(stdout,'(/,a,f19.10)') ' Galitskii-Migdal Total energy (Ha): ',en%tot - en%rpa + en%gw
     endif

     if( .NOT. ( calc_type%selfenergy_approx == GnW0 .AND. istep_gw < nstep_gw ) ) then
       call destroy_spectral_function(wpol)
     endif

     if( has_small_basis ) then
       !
       ! Output the G0W0 results in the small basis first
       allocate(energy_qp_z(nstate,nspin))
       allocate(energy_qp_new(nstate,nspin))
       allocate(zz(nstate,nspin))
       call find_qp_energy_linearization(se,exchange_m_vxc_diag,energy,energy_qp_z,zz)
       call find_qp_energy_graphical(se,exchange_m_vxc_diag,energy,energy_qp_new)
       call output_qp_energy('GW small basis',energy,exchange_m_vxc_diag,1,se,energy_qp_z,energy_qp_new,zz)
       deallocate(zz)
       deallocate(energy_qp_z)
       call output_new_homolumo('GW small basis',nstate,occupation,energy_qp_new,nsemin,nsemax)
       deallocate(energy_qp_new)

       call init_selfenergy_grid(static_selfenergy,energy,se2)
       call init_selfenergy_grid(static_selfenergy,energy,se3)

       ! Sigma^2 = Sigma^{1-ring}_small
       call onering_selfenergy(nstate_small,basis,occupation(1:nstate_small,:), &
                               energy_g(1:nstate_small,:),c_matrix(:,1:nstate_small,:),se2,en%mp2)

       ! Reset wavefunctions, eigenvalues and number of virtual orbitals in G
       call destroy_fno(basis,nstate,energy,c_matrix)
       energy_g(:,:) = energy(:,:)
       call selfenergy_set_state_range(nstate,occupation)

       ! Sigma^3 = Sigma^{1-ring}_big
       call onering_selfenergy(nstate,basis,occupation,energy_g,c_matrix,se3,en%mp2)

       if( print_sigma_ ) then
         call write_selfenergy_omega('selfenergy_GW_small'   ,exchange_m_vxc_diag,occupation,energy_g,se)
         call write_selfenergy_omega('selfenergy_1ring_big'  ,exchange_m_vxc_diag,occupation,energy_g,se3)
         call write_selfenergy_omega('selfenergy_1ring_small',exchange_m_vxc_diag,occupation,energy_g,se2)
       endif

       !
       ! Extrapolated Sigma(omega) = Sigma^{GW}_small(omega) + Sigma^{1-ring}_big(0) - Sigma^{1-ring}_small(0)
       do iomega=-se%nomega,se%nomega
         se%sigma(iomega,:,:) = se%sigma(iomega,:,:) + se3%sigma(0,:,:) - se2%sigma(0,:,:)
       enddo

       call destroy_selfenergy_grid(se2)
       call destroy_selfenergy_grid(se3)

     endif

   endif

   !
   ! GWGamma
   !
   if( calc_type%selfenergy_approx == G0W0GAMMA0 .OR. calc_type%selfenergy_approx == G0W0SOX0 ) then
     call init_spectral_function(nstate,occupation,0,wpol)
     call read_spectral_function(wpol,reading_status)
     ! If reading has failed, then do the calculation
     if( reading_status /= 0 ) then
       call polarizability(.FALSE.,.TRUE.,basis,nstate,occupation,energy_w,c_matrix,en%rpa,wpol)
     endif

     call gw_selfenergy(GW,nstate,basis,occupation,energy_g,c_matrix,wpol,se,en%gw)

     !
     ! Output the G0W0 results first
     allocate(energy_qp_z(nstate,nspin))
     allocate(energy_qp_new(nstate,nspin))
     allocate(zz(nstate,nspin))
     call find_qp_energy_linearization(se,exchange_m_vxc_diag,energy,energy_qp_z,zz)
     call find_qp_energy_graphical(se,exchange_m_vxc_diag,energy,energy_qp_new)
     call output_qp_energy('GW',energy,exchange_m_vxc_diag,1,se,energy_qp_z,energy_qp_new,zz)
     deallocate(zz)
     deallocate(energy_qp_z)
     call output_new_homolumo('GW',nstate,occupation,energy_qp_new,nsemin,nsemax)
     deallocate(energy_qp_new)


     call gwgamma_selfenergy(nstate,basis,occupation,energy_g,c_matrix,wpol,se)
     call destroy_spectral_function(wpol)
   endif

   !
   ! selfenergy = GWSOX
   !
   if( calc_type%selfenergy_approx == GWSOX ) then
     !
     ! First perform a standard GW calculation
     !
     call init_spectral_function(nstate,occupation,0,wpol)
     call read_spectral_function(wpol,reading_status)
     ! If reading has failed, then do the calculation
     if( reading_status /= 0 ) then
       call polarizability(.FALSE.,.TRUE.,basis,nstate,occupation,energy_w,c_matrix,en%rpa,wpol)
     endif
     call gw_selfenergy(GW,nstate,basis,occupation,energy_g,c_matrix,wpol,se,en%gw)

     !
     ! Second perform a standard SOX calculation
     !
     call init_selfenergy_grid(calc_type%selfenergy_technique,energy_g,se_sox)
     call pt2_selfenergy(SOX,nstate,basis,occupation,energy_g,c_matrix,se_sox,en%mp2)


     !
     ! Finally add up the contributions and then destroy the se_sox object
     !
     se%sigma(:,:,:) = se%sigma(:,:,:) + se_sox%sigma(:,:,:)

     call destroy_selfenergy_grid(se_sox)

   endif

   !
   ! Selfenergy = PT2
   !
   if(   calc_type%selfenergy_approx == PT2       &
    .OR. calc_type%selfenergy_approx == ONE_RING  &
    .OR. calc_type%selfenergy_approx == SOX ) then

     call pt2_selfenergy(calc_type%selfenergy_approx,nstate,basis,occupation,energy_g,c_matrix,se,en%mp2)

     if( ABS( en%mp2 ) > 1.0e-8 ) then
       write(stdout,'(a,2x,f19.10)') ' MP2 Energy       (Ha):',en%mp2
       write(stdout,*)
       en%tot = en%nuc_nuc + en%kin + en%nuc + en%hart + en%exx + en%mp2

       write(stdout,'(a,2x,f19.10)') ' MP2 Total Energy (Ha):',en%tot
       write(stdout,'(a,2x,f19.10)') ' SE+MP2  Total En (Ha):',en%tot+en%se
       write(stdout,*)
     endif

   endif

   !
   ! Selfenergy = PT3 or 2-rings
   !
   if( calc_type%selfenergy_approx == PT3 .OR. calc_type%selfenergy_approx == TWO_RINGS ) then
     call pt3_selfenergy(calc_type%selfenergy_approx,calc_type%selfenergy_technique,nstate,basis,occupation,energy_g,c_matrix,se,en%mp2)
   endif

   !
   ! selfenergy = GWPT3
   !
   if( calc_type%selfenergy_approx == GWPT3 ) then
     !
     ! First perform a standard GW calculation
     !
     call init_spectral_function(nstate,occupation,0,wpol)
     call read_spectral_function(wpol,reading_status)
     ! If reading has failed, then do the calculation
     if( reading_status /= 0 ) then
       call polarizability(.FALSE.,.TRUE.,basis,nstate,occupation,energy_w,c_matrix,en%rpa,wpol)
     endif
     call gw_selfenergy(GW,nstate,basis,occupation,energy_g,c_matrix,wpol,se,en%gw)

     !
     ! Second perform a PT3 calculation minus the ring diagrams
     !
     call init_selfenergy_grid(calc_type%selfenergy_technique,energy_g,se_gwpt3)
     call pt3_selfenergy(GWPT3,calc_type%selfenergy_technique,nstate,basis,occupation,energy_g,c_matrix,se_gwpt3,en%mp2)

     !
     ! Finally add up the contributions and then destroy the se_sox object
     !
     se%sigma(:,:,:) = se%sigma(:,:,:) + se_gwpt3%sigma(:,:,:)

     call destroy_selfenergy_grid(se_gwpt3)

   endif

   !
   ! EXPERIMENTAL COHSEX implementation
   ! final evaluation for perturbative COHSEX
   !
   if( calc_type%selfenergy_approx == COHSEX_DEVEL .OR. calc_type%selfenergy_approx == TUNED_COHSEX ) then

     if( .NOT. has_auxil_basis ) call die('cohsex needs an auxiliary basis')
     call init_spectral_function(nstate,occupation,1,wpol)
     call calculate_eri_3center_eigen(c_matrix,ncore_W+1,nhomo_W,nlumo_W,nvirtual_W-1)
     !
     ! Calculate v^{1/2} \chi v^{1/2}
     call static_polarizability(nstate,occupation,energy_w,wpol)

     call destroy_eri_3center_eigen()

     !
     allocate(matrix_tmp(basis%nbf,basis%nbf,nspin))
     allocate(sigc(nstate,nspin))

#ifdef COHSEX_DEVEL
     ! Calculate the DFT potential part
     if( ABS( delta_cohsex ) > 1.0e-6_dp ) then

       allocate(p_matrix(basis%nbf,basis%nbf,nspin))
       call init_dft_grid(basis,grid_level,.TRUE.,.FALSE.,BATCH_SIZE)
       call setup_density_matrix(basis%nbf,nstate,c_matrix,occupation,p_matrix)

       ! Override the DFT XC correlation settings
       calc_type_tmp = calc_type
       call init_dft_type('HJSx',calc_type_tmp)
#ifdef HAVE_LIBXC
       call xc_f90_gga_x_hjs_set_par(calc_type_tmp%xc_func(1),1.0_dp/rcut_mbpt)
#endif
       call dft_exc_vxc_batch(BATCH_SIZE,basis,occupation,c_matrix,matrix_tmp,exc)

       write(stdout,*) '===== SigX SR ======'
       do ispin=1,nspin
         do istate=1,nstate
           sigc(istate,ispin) = DOT_PRODUCT( c_matrix(:,istate,ispin) , &
                                     MATMUL( matrix_tmp(:,:,ispin) , c_matrix(:,istate,ispin ) ) )
           write(stdout,*) istate,ispin,sigc(istate,ispin) * Ha_eV
         enddo
         sigc(istate,ispin) = sigc(istate,ispin) * delta_cohsex
       enddo
       write(stdout,*) '===================='

       deallocate(p_matrix)
       call destroy_dft_grid()

     else

       sigc(:,:) = 0.0_dp

     endif

#endif

     call cohsex_selfenergy(nstate,basis,occupation, &
                            c_matrix,wpol,se)


     !
     ! A section under development for the range-separated RPA
     if( calc_type%is_lr_mbpt ) then

       ! 2-center integrals
       call calculate_eri_2center_scalapack(auxil_basis,rcut_mbpt)
       ! 3-center integrals
       call calculate_eri_3center_scalapack(basis,auxil_basis,rcut_mbpt)

       call cohsex_selfenergy_lr(nstate,basis,occupation, &
                                 c_matrix,wpol,se)
     endif

     deallocate(matrix_tmp)
     deallocate(sigc)

   endif ! COHSEX
   !
   ! end of EXPERIMENTAL COHSEX implementation
   !


   !
   ! Output the quasiparticle energies, the self-energy etc.
   !
   if( print_sigma_ ) then
     call write_selfenergy_omega('selfenergy_'//TRIM(selfenergy_tag),exchange_m_vxc_diag,occupation,energy_g,se)
   endif


   allocate(energy_qp_new(nstate,nspin))

   if( calc_type%selfenergy_technique == EVSC ) then
     call find_qp_energy_linearization(se,exchange_m_vxc_diag,energy,energy_qp_new)
     call output_qp_energy(TRIM(selfenergy_tag),energy,exchange_m_vxc_diag,1,se,energy_qp_new)
   else
     select case(calc_type%selfenergy_approx)
     case(GW,PT2,PT3,ONE_RING,TWO_RINGS,SOX,G0W0Gamma0,G0W0SOX0,G0W0_IOMEGA,GWSOX,GWPT3)
       allocate(energy_qp_z(nstate,nspin))
       allocate(zz(nstate,nspin))
       call find_qp_energy_linearization(se,exchange_m_vxc_diag,energy,energy_qp_z,zz)
       call find_qp_energy_graphical(se,exchange_m_vxc_diag,energy,energy_qp_new)

       call output_qp_energy(TRIM(selfenergy_tag),energy,exchange_m_vxc_diag,1,se,energy_qp_z,energy_qp_new,zz)
       deallocate(zz)
       deallocate(energy_qp_z)

     case(GnWn,GnW0,GV,COHSEX,COHSEX_DEVEL,TUNED_COHSEX)
       call find_qp_energy_linearization(se,exchange_m_vxc_diag,energy,energy_qp_new)
       call output_qp_energy(TRIM(selfenergy_tag),energy,exchange_m_vxc_diag,1,se,energy_qp_new)
     end select
   endif

   !
   ! Write the QP energies on disk: ENERGY_QP file
   !
   call write_energy_qp(nstate,energy_qp_new)

   !
   ! Output the new HOMO and LUMO energies
   !
   call output_new_homolumo(TRIM(selfenergy_tag),nstate,occupation,energy_qp_new,nsemin,nsemax)



   deallocate(energy_qp_new)



   !
   ! Deallocations
   !
   call destroy_selfenergy_grid(se)

   ! Synchronization of all CPUs before going on
   call barrier_world()
 enddo ! nstep_gw


end subroutine selfenergy_evaluation


!=========================================================================
