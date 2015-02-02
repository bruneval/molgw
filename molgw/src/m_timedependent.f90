!=========================================================================
#include "macros.h"
!=========================================================================
module m_timedependent
 use m_definitions
 use m_timing
 use m_warning
 use m_inputparam


contains


!=========================================================================
subroutine polarizability(basis,prod_basis,auxil_basis,occupation,energy,c_matrix,rpa_correlation,wpol_out)
 use m_mpi
 use m_tools
 use m_basis_set
 use m_spectral_function
 use m_gw
 implicit none

 type(basis_set),intent(in)            :: basis,prod_basis,auxil_basis
 real(dp),intent(in)                   :: occupation(basis%nbf,nspin)
 real(dp),intent(in)                   :: energy(basis%nbf,nspin),c_matrix(basis%nbf,basis%nbf,nspin)
 real(dp),intent(out)                  :: rpa_correlation
 type(spectral_function),intent(out)   :: wpol_out
!=====
 integer                 :: t_ij
 type(spectral_function) :: wpol_static
 integer                 :: nmat
 real(dp)                :: alpha_local
 real(dp),allocatable    :: amb_matrix(:,:),apb_matrix(:,:)
 real(dp),allocatable    :: eigenvalue(:),eigenvector(:,:),eigenvector_inv(:,:)
 real(dp)                :: energy_qp(basis%nbf,nspin)
 logical                 :: is_tddft
 logical                 :: is_ij
 logical                 :: is_rpa
 logical                 :: has_manual_tdhf
!=====

 call start_clock(timing_pola)

 WRITE_MASTER(*,'(/,a)') ' Calculating the polarizability'
 
 ! Set up all the switches to be able to treat
 ! GW, BSE, TDHF, TDDFT (semilocal or hybrid)

 !
 ! Set up flag is_rpa
 inquire(file='manual_rpa',exist=is_rpa)
 if(is_rpa) then
   msg='RPA calculation is enforced'
   call issue_warning(msg)
 endif
 is_rpa   = calc_type%is_gw .OR. is_rpa

 ! 
 ! Set up flag is_tddft
 is_tddft = calc_type%is_td .AND. calc_type%is_dft .AND. .NOT. is_rpa

 ! 
 ! Set up exchange content alpha_local
 ! manual_tdhf can override anything
 inquire(file='manual_tdhf',exist=has_manual_tdhf)
 if(has_manual_tdhf) then
   open(unit=18,file='manual_tdhf',status='old')
   read(18,*) alpha_local
   close(18)
   WRITE_ME(msg,'(a,f12.6,3x,f12.6)') 'calculating the TDHF polarizability with alpha ',alpha_local
   call issue_warning(msg)
 else
   if(is_rpa) then
     alpha_local = 0.0_dp
   else if(is_tddft) then
     alpha_local = alpha_hybrid
   else ! TDHF or BSE case
     alpha_local = 1.0_dp
   endif
 endif


 call start_clock(timing_build_h2p)

 ! Obtain the number of transition = the size of the matrix
 call init_spectral_function(basis%nbf,occupation,wpol_out)

 !
 ! Prepare BSE calculations
 ! static screening + GW quasiparticle energies
 !
 if( calc_type%is_bse .AND. .NOT. is_rpa ) then
   ! Set up energy_qp and wpol_static
   call prepare_bse(basis%nbf,energy,occupation,energy_qp,wpol_static)
 else
   ! For any other type of calculation, just fill energy_qp array with energy
   energy_qp(:,:) = energy(:,:)
 endif


 nmat = wpol_out%npole/2
 allocate(apb_matrix(nmat,nmat))
 allocate(amb_matrix(nmat,nmat))

 !
 ! Build the (A+B) and (A-B) matrices in 3 steps
 ! to span all the possible approximations
 !
 WRITE_MASTER(*,'(/,a)') ' Build the electron-hole hamiltonian'
 call build_amb_apb_common(basis%nbf,c_matrix,energy_qp,wpol_out,alpha_local,nmat,amb_matrix,apb_matrix)
 if(is_tddft) &
   call build_apb_tddft(basis,c_matrix,occupation,wpol_out,nmat,apb_matrix)
 if(calc_type%is_bse .AND. .NOT. is_rpa) then
   call build_amb_apb_bse(basis%nbf,prod_basis,c_matrix,wpol_out,wpol_static,nmat,amb_matrix,apb_matrix)
   call destroy_spectral_function(wpol_static)
 endif

 !
 ! First part of the RPA correlation energy: sum over diagonal terms
 rpa_correlation = 0.0_dp
 do t_ij=1,nmat
   rpa_correlation = rpa_correlation - 0.25_dp * ( apb_matrix(t_ij,t_ij) + amb_matrix(t_ij,t_ij) )
 enddo

 !
 ! Warning if Tamm-Dancoff flag is on
 if(calc_type%is_tda) then
   msg='Tamm-Dancoff approximation is switched on'
   call issue_warning(msg)
   ! Tamm-Dancoff approximation consists in setting B matrix to zero
   ! Then A+B = A-B = A
   apb_matrix(:,:) = 0.5_dp * ( apb_matrix(:,:) + amb_matrix(:,:) )
   amb_matrix(:,:) = apb_matrix(:,:) 
 endif

 call stop_clock(timing_build_h2p)


 allocate(eigenvector(wpol_out%npole,wpol_out%npole))
 allocate(eigenvector_inv(wpol_out%npole,wpol_out%npole))
 allocate(eigenvalue(wpol_out%npole))

 !
 ! Diago using the 4 block structure and the symmetry of each block
 call start_clock(timing_diago_h2p)
 if(.TRUE.) then
   call diago_4blocks_sqrt(nmat,amb_matrix,apb_matrix,wpol_out%npole,eigenvalue,eigenvector,eigenvector_inv)
 else
   call diago_4blocks_chol(nmat,amb_matrix,apb_matrix,wpol_out%npole,eigenvalue,eigenvector,eigenvector_inv)
 endif
 call stop_clock(timing_diago_h2p)

 !
 ! Second part of the RPA correlation energy: sum over positive eigenvalues
 rpa_correlation = rpa_correlation + 0.50_dp * SUM( eigenvalue(1:nmat) )
 if(is_rpa) then
  WRITE_MASTER(*,'(/,a)') ' Calculate the RPA energy using the Tamm-Dancoff decomposition'
  WRITE_MASTER(*,'(a)')   ' Eq. (9) from J. Chem. Phys. 132, 234114 (2010)'
  WRITE_MASTER(*,'(/,a,f14.8)') ' RPA energy [Ha]: ',rpa_correlation
 endif

 WRITE_MASTER(*,'(/,a,f14.8)') ' Lowest neutral excitation energy [eV]',MINVAL(ABS(eigenvalue(:)))*Ha_eV


 deallocate(apb_matrix,amb_matrix)

 !
 ! Calculate the optical sprectrum
 ! and the dynamic dipole tensor
 !
 if( calc_type%is_td .OR. calc_type%is_bse ) &
   call optical_spectrum(basis,prod_basis,occupation,c_matrix,wpol_out,eigenvector,eigenvector_inv,eigenvalue)

 !
 ! Calculate Wp= v * chi * v    if necessary
 ! and then write it down on file
 !
 if( print_specfunc .OR. calc_type%is_gw ) then
   if( is_auxil_basis) then
     call chi_to_sqrtvchisqrtv_auxil(basis%nbf,auxil_basis%nbf,occupation,c_matrix,eigenvector,eigenvector_inv,eigenvalue,wpol_out)
   else
     call chi_to_vchiv(basis%nbf,prod_basis,occupation,c_matrix,eigenvector,eigenvector_inv,eigenvalue,wpol_out)
   endif
 
   ! If requested write the spectral function on file
   if( print_specfunc ) call write_spectral_function(wpol_out)

 endif

 if( .NOT. calc_type%is_gw ) call destroy_spectral_function(wpol_out)

 if(allocated(eigenvector))     deallocate(eigenvector)
 if(allocated(eigenvector_inv)) deallocate(eigenvector_inv)
 if(allocated(eigenvalue))      deallocate(eigenvalue)

 call stop_clock(timing_pola)


end subroutine polarizability


!=========================================================================
subroutine build_amb_apb_common(nbf,c_matrix,energy,wpol,alpha_local,nmat,amb_matrix,apb_matrix)
 use m_spectral_function
 use m_eri
 use m_tools 
 implicit none

 integer,intent(in)                 :: nbf
 real(dp),intent(in)                :: energy(nbf,nspin)
 real(dp),intent(in)                :: c_matrix(nbf,nbf,nspin)
 type(spectral_function),intent(in) :: wpol
 real(dp),intent(in)                :: alpha_local
 integer,intent(in)                 :: nmat
 real(dp),intent(out)               :: amb_matrix(nmat,nmat),apb_matrix(nmat,nmat)
!=====
 integer              :: t_ij,t_kl
 integer              :: istate,jstate,kstate,lstate
 integer              :: ijspin,klspin
 integer              :: ijstate_min
 real(dp),allocatable :: eri_eigenstate_ijmin(:,:,:,:)
 real(dp)             :: eri_eigen_ijkl
 real(dp)             :: eri_eigen_ikjl,eri_eigen_iljk
 logical              :: is_ij
!=====

 call start_clock(timing_build_common)

 WRITE_MASTER(*,'(a)') ' Build Common part: Energies + Hartree + possibly Exchange'
 WRITE_MASTER(*,'(a,f8.3)') ' Content of Exchange: ',alpha_local

 if( .NOT. is_auxil_basis) then
   allocate(eri_eigenstate_ijmin(nbf,nbf,nbf,nspin))
   ! Set this to zero and then enforce the calculation of the first series of
   ! Coulomb integrals
   eri_eigenstate_ijmin(:,:,:,:) = 0.0_dp
 endif

 !
 ! Set up energy+hartree+exchange contributions to matrices (A+B) and (A-B) 
 !
 do t_ij=1,nmat ! only resonant transition
   istate = wpol%transition_table(1,t_ij)
   jstate = wpol%transition_table(2,t_ij)
   ijspin = wpol%transition_table(3,t_ij)

   if( .NOT. is_auxil_basis ) then
     ijstate_min = MIN(istate,jstate)
     is_ij = (ijstate_min == istate)
     call transform_eri_basis(nspin,c_matrix,ijstate_min,ijspin,eri_eigenstate_ijmin)
   endif

   do t_kl=1,nmat ! only resonant transition
     kstate = wpol%transition_table(1,t_kl)
     lstate = wpol%transition_table(2,t_kl)
     klspin = wpol%transition_table(3,t_kl)


     if(is_auxil_basis) then
       eri_eigen_ijkl = eri_eigen_ri(istate,jstate,ijspin,kstate,lstate,klspin)
     else
       if(is_ij) then ! treating (i,j)
         eri_eigen_ijkl = eri_eigenstate_ijmin(jstate,kstate,lstate,klspin)
       else           ! treating (j,i)
         eri_eigen_ijkl = eri_eigenstate_ijmin(istate,kstate,lstate,klspin)
       endif
     endif

     apb_matrix(t_ij,t_kl) = 2.0_dp * eri_eigen_ijkl * spin_fact
     amb_matrix(t_ij,t_kl) = 0.0_dp

     if( alpha_local > 1.0e-6_dp ) then
       if(ijspin==klspin) then
         if(is_auxil_basis) then
           eri_eigen_ikjl = eri_eigen_ri(istate,kstate,ijspin,jstate,lstate,klspin)
           eri_eigen_iljk = eri_eigen_ri(istate,lstate,ijspin,jstate,kstate,klspin)
         else
           if(is_ij) then
             eri_eigen_ikjl = eri_eigenstate_ijmin(kstate,jstate,lstate,klspin)
             eri_eigen_iljk = eri_eigenstate_ijmin(lstate,jstate,kstate,klspin)
           else
             eri_eigen_ikjl = eri_eigenstate_ijmin(lstate,istate,kstate,klspin)
             eri_eigen_iljk = eri_eigenstate_ijmin(kstate,istate,lstate,klspin)
           endif
         endif
         apb_matrix(t_ij,t_kl) = apb_matrix(t_ij,t_kl) - eri_eigen_ikjl * alpha_local - eri_eigen_iljk * alpha_local
         amb_matrix(t_ij,t_kl) = amb_matrix(t_ij,t_kl) - eri_eigen_ikjl * alpha_local + eri_eigen_iljk * alpha_local
       endif
     endif

   enddo 

   apb_matrix(t_ij,t_ij) =  apb_matrix(t_ij,t_ij) + ( energy(jstate,ijspin) - energy(istate,ijspin) )
   amb_matrix(t_ij,t_ij) =  amb_matrix(t_ij,t_ij) + ( energy(jstate,ijspin) - energy(istate,ijspin) )

 enddo 

 if(allocated(eri_eigenstate_ijmin)) deallocate(eri_eigenstate_ijmin)


 call stop_clock(timing_build_common)

end subroutine build_amb_apb_common


!=========================================================================
subroutine build_apb_tddft(basis,c_matrix,occupation,wpol,nmat,apb_matrix)
 use m_spectral_function
 use m_basis_set
 use m_dft_grid
 implicit none

 type(basis_set),intent(in)         :: basis
 real(dp),intent(in)                :: c_matrix(basis%nbf,basis%nbf,nspin)
 real(dp),intent(in)                :: occupation(basis%nbf,nspin)
 type(spectral_function),intent(in) :: wpol
 integer,intent(in)                 :: nmat
 real(dp),intent(inout)             :: apb_matrix(nmat,nmat)
!=====
 integer              :: t_ij,t_kl
 integer              :: istate,jstate,kstate,lstate
 integer              :: ijspin,klspin
 logical              :: require_gradient
 real(dp),allocatable :: grad_ij(:,:,:),grad_kl(:,:,:)
 real(dp),allocatable :: dot_ij_kl(:,:),dot_rho_ij(:,:),dot_rho_kl(:,:)
 real(dp),allocatable :: v2rho2(:,:)
 real(dp),allocatable :: vsigma(:,:)
 real(dp),allocatable :: v2rhosigma(:,:)
 real(dp),allocatable :: v2sigma2(:,:)
 real(dp),allocatable :: wf_r(:,:,:)
 real(dp),allocatable :: wf_gradr(:,:,:,:)
 real(dp),allocatable :: rho_gradr(:,:,:)
 real(dp)             :: xctmp
!=====

 call start_clock(timing_build_tddft)

 WRITE_MASTER(*,'(a)') ' Build fxc part'

 !
 ! Prepare TDDFT calculations
 call prepare_tddft(basis,c_matrix,occupation,v2rho2,vsigma,v2rhosigma,v2sigma2,wf_r,wf_gradr,rho_gradr)
 require_gradient = .FALSE.
 if(allocated(v2sigma2)) then ! GGA case
   require_gradient = .TRUE.
   allocate(grad_ij(3,ngrid,nspin))
   allocate(grad_kl(3,ngrid,nspin))
   allocate(dot_ij_kl(ngrid,nspin))
   allocate(dot_rho_ij(ngrid,nspin))
   allocate(dot_rho_kl(ngrid,nspin))
 endif

 if(require_gradient .AND. nspin>1) then
   stop'spin in TD-GGA not implemented yet'
 endif


 !
 ! Set up fxc contributions to matrices (A+B)
 !
 do t_ij=1,nmat ! only resonant transition
   istate = wpol%transition_table(1,t_ij)
   jstate = wpol%transition_table(2,t_ij)
   ijspin = wpol%transition_table(3,t_ij)

   do t_kl=t_ij,nmat  ! use the symmetry of (A+B)
     kstate = wpol%transition_table(1,t_kl)
     lstate = wpol%transition_table(2,t_kl)
     klspin = wpol%transition_table(3,t_kl)


     xctmp = SUM(  wf_r(:,istate,ijspin) * wf_r(:,jstate,ijspin) &
                        * wf_r(:,kstate,klspin) * wf_r(:,lstate,klspin) &
                        * v2rho2(:,ijspin) )                            &
                        * 4.0_dp


     if(require_gradient) then

       grad_ij(1,:,ijspin) = wf_gradr(1,:,istate,ijspin) * wf_r(:,jstate,ijspin) + wf_gradr(1,:,jstate,ijspin) * wf_r(:,istate,ijspin)
       grad_ij(2,:,ijspin) = wf_gradr(2,:,istate,ijspin) * wf_r(:,jstate,ijspin) + wf_gradr(2,:,jstate,ijspin) * wf_r(:,istate,ijspin)
       grad_ij(3,:,ijspin) = wf_gradr(3,:,istate,ijspin) * wf_r(:,jstate,ijspin) + wf_gradr(3,:,jstate,ijspin) * wf_r(:,istate,ijspin)
       grad_kl(1,:,klspin) = wf_gradr(1,:,kstate,klspin) * wf_r(:,lstate,klspin) + wf_gradr(1,:,lstate,klspin) * wf_r(:,kstate,klspin)
       grad_kl(2,:,klspin) = wf_gradr(2,:,kstate,klspin) * wf_r(:,lstate,klspin) + wf_gradr(2,:,lstate,klspin) * wf_r(:,kstate,klspin)
       grad_kl(3,:,klspin) = wf_gradr(3,:,kstate,klspin) * wf_r(:,lstate,klspin) + wf_gradr(3,:,lstate,klspin) * wf_r(:,kstate,klspin)
       dot_ij_kl(:,ijspin) = grad_ij(1,:,ijspin) * grad_kl(1,:,klspin) + grad_ij(2,:,ijspin) * grad_kl(2,:,klspin) &
                            + grad_ij(3,:,ijspin) * grad_kl(3,:,klspin)
       dot_rho_ij(:,ijspin) = rho_gradr(1,:,1) * grad_ij(1,:,ijspin) + rho_gradr(2,:,1) * grad_ij(2,:,ijspin)  &
                             + rho_gradr(3,:,1) * grad_ij(3,:,ijspin)
       dot_rho_kl(:,klspin) = rho_gradr(1,:,1) * grad_kl(1,:,klspin) + rho_gradr(2,:,1) * grad_kl(2,:,klspin)  &
                             + rho_gradr(3,:,1) * grad_kl(3,:,klspin)

       xctmp = xctmp   &
             + SUM( dot_ij_kl(:,1) * 6.0_dp * vsigma(:,1) ) &
             + SUM( dot_rho_ij(:,1) * dot_rho_kl(:,1) * 9.0_dp * v2sigma2(:,1) ) &
             + SUM( dot_rho_ij(:,1) * dot_rho_kl(:,1) * 9.0_dp * v2sigma2(:,1) ) &
             + SUM( ( wf_r(:,istate,ijspin) * wf_r(:,jstate,ijspin) * dot_rho_kl(:,1)   &
                    + wf_r(:,kstate,klspin) * wf_r(:,lstate,klspin) * dot_rho_ij(:,1) ) &
                       * 6.0_dp * v2rhosigma(:,1) )

     endif

     apb_matrix(t_ij,t_kl) = apb_matrix(t_ij,t_kl) + xctmp
     ! use the symmetry of (A+B)
     if( t_ij /= t_kl ) apb_matrix(t_kl,t_ij) = apb_matrix(t_kl,t_ij) + xctmp

   enddo
 enddo


 deallocate(wf_r)

 if(require_gradient) then
   deallocate(grad_ij,grad_kl)
   deallocate(dot_ij_kl,dot_rho_ij,dot_rho_kl)
   deallocate(v2rho2)
   deallocate(vsigma)
   deallocate(v2rhosigma)
   deallocate(v2sigma2)
   deallocate(wf_gradr)
   deallocate(rho_gradr)
 endif


 call stop_clock(timing_build_tddft)

end subroutine build_apb_tddft


!=========================================================================
subroutine build_amb_apb_bse(nbf,prod_basis,c_matrix,wpol,wpol_static,nmat,amb_matrix,apb_matrix)
 use m_spectral_function
 use m_basis_set
 use m_eri
 use m_tools 
 implicit none

 integer,intent(in)                 :: nbf
 type(basis_set),intent(in)         :: prod_basis
 real(dp),intent(in)                :: c_matrix(nbf,nbf,nspin)
 type(spectral_function),intent(in) :: wpol,wpol_static
 integer,intent(in)                 :: nmat
 real(dp),intent(out)               :: amb_matrix(nmat,nmat),apb_matrix(nmat,nmat)
!=====
 integer              :: t_ij,t_kl
 integer              :: istate,jstate,kstate,lstate
 integer              :: ijspin,klspin
 integer              :: kbf
 real(dp),allocatable :: bra(:),ket(:)
 real(dp),allocatable :: bra_auxil(:,:,:,:),ket_auxil(:,:,:,:)
 real(dp)             :: wtmp
!=====

 call start_clock(timing_build_bse)

 WRITE_MASTER(*,'(a)') ' Build W part'
 !
 ! Prepare the bra and ket for BSE
 allocate(bra(wpol_static%npole),ket(wpol_static%npole))

 if(is_auxil_basis) then
   allocate(bra_auxil(wpol_static%npole,ncore_W+1:nvirtual_W-1,ncore_W+1:nvirtual_W-1,nspin))
   allocate(ket_auxil(wpol_static%npole,ncore_W+1:nvirtual_W-1,ncore_W+1:nvirtual_W-1,nspin))
   do ijspin=1,nspin
     do istate=ncore_W+1,nvirtual_W-1 
       do jstate=ncore_W+1,nvirtual_W-1

         ! Here transform (sqrt(v) * chi * sqrt(v)) into  (v * chi * v)
         bra_auxil(:,istate,jstate,ijspin) = MATMUL( wpol_static%residu_left (:,:) , eri_3center_eigen(:,istate,jstate,ijspin) )
         ket_auxil(:,istate,jstate,ijspin) = MATMUL( wpol_static%residu_right(:,:) , eri_3center_eigen(:,istate,jstate,ijspin) )

       enddo
     enddo
   enddo
 endif

 !
 ! Set up fxc contributions to matrices (A+B)
 !
 do t_ij=1,nmat ! only resonant transition
   istate = wpol%transition_table(1,t_ij)
   jstate = wpol%transition_table(2,t_ij)
   ijspin = wpol%transition_table(3,t_ij)

   do t_kl=t_ij,nmat ! only resonant transition
     kstate = wpol%transition_table(1,t_kl)
     lstate = wpol%transition_table(2,t_kl)
     klspin = wpol%transition_table(3,t_kl)

     if(ijspin/=klspin) cycle

     if(.NOT. is_auxil_basis) then
       kbf = prod_basis%index_prodbasis(istate,kstate)+prod_basis%nbf*(ijspin-1)
       bra(:) = wpol_static%residu_left (:,kbf)
       kbf = prod_basis%index_prodbasis(jstate,lstate)+prod_basis%nbf*(klspin-1)
       ket(:) = wpol_static%residu_right(:,kbf)
     else
       bra(:) = bra_auxil(:,istate,kstate,ijspin) 
       ket(:) = ket_auxil(:,jstate,lstate,klspin)
     endif

     wtmp =  SUM( bra(:)*ket(:)/(-wpol_static%pole(:)) )
     apb_matrix(t_ij,t_kl) =  apb_matrix(t_ij,t_kl) - wtmp
     amb_matrix(t_ij,t_kl) =  amb_matrix(t_ij,t_kl) - wtmp
     if( t_ij/=t_kl) then
       apb_matrix(t_kl,t_ij) =  apb_matrix(t_kl,t_ij) - wtmp
       amb_matrix(t_kl,t_ij) =  amb_matrix(t_kl,t_ij) - wtmp
     endif

     if(.NOT. is_auxil_basis) then
       kbf = prod_basis%index_prodbasis(istate,lstate)+prod_basis%nbf*(ijspin-1)
       bra(:) = wpol_static%residu_left (:,kbf)
       kbf = prod_basis%index_prodbasis(jstate,kstate)+prod_basis%nbf*(klspin-1)
       ket(:) = wpol_static%residu_right(:,kbf)
     else
       bra(:) = bra_auxil(:,istate,lstate,ijspin) 
       ket(:) = ket_auxil(:,jstate,kstate,klspin)
     endif

     wtmp =  SUM( bra(:)*ket(:)/(-wpol_static%pole(:)) )
     apb_matrix(t_ij,t_kl) =  apb_matrix(t_ij,t_kl) - wtmp
     amb_matrix(t_ij,t_kl) =  amb_matrix(t_ij,t_kl) + wtmp
     if( t_ij/=t_kl) then
       apb_matrix(t_kl,t_ij) =  apb_matrix(t_kl,t_ij) - wtmp
       amb_matrix(t_kl,t_ij) =  amb_matrix(t_kl,t_ij) + wtmp
     endif


   enddo
 enddo

 deallocate(bra,ket)
 if(allocated(bra_auxil))                deallocate(bra_auxil)
 if(allocated(ket_auxil))                deallocate(ket_auxil)


 call stop_clock(timing_build_bse)


end subroutine build_amb_apb_bse


!=========================================================================
subroutine diago_4blocks_sqrt(nmat,amb_matrix,apb_matrix,npole,eigenvalue,eigenvector,eigenvector_inv)
 use m_spectral_function
 use m_eri
 use m_tools 
 implicit none

 integer,intent(in)     :: nmat,npole
 real(dp),intent(inout) :: amb_matrix(nmat,nmat),apb_matrix(nmat,nmat)
 real(dp),intent(out)   :: eigenvalue(npole)
 real(dp),intent(out)   :: eigenvector(npole,npole)
 real(dp),intent(out)   :: eigenvector_inv(npole,npole)
!=====
 integer              :: t_kl
 real(dp),allocatable :: amb_eigval(:),bigomega(:)
 real(dp),allocatable :: amb_matrix_sqrt(:,:),amb_matrix_sqrtm1(:,:)
 real(dp),allocatable :: cc_matrix(:,:)
 real(dp),allocatable :: bigx(:,:),bigy(:,:),cc_matrix_bigomega(:,:)
!=====

 WRITE_MASTER(*,'(/,a)') ' Performing the block diago with square root of matrices'
 allocate(cc_matrix(nmat,nmat))
 allocate(amb_eigval(nmat))


 !
 ! Calculate (A-B)^{1/2}
 ! First diagonalize (A-B):
 ! (A-B) R = R D
 ! (A-B) is real symmetric, hence R is orthogonal R^{-1} = tR
 ! (A-B)       = R D tR 
 ! (A-B)^{1/2} = R D^{1/2} tR 
 WRITE_MASTER(*,'(a,i8,a,i8)') ' Diago to get (A - B)^{1/2}                   ',nmat,' x ',nmat
 call diagonalize(nmat,amb_matrix,amb_eigval)

 allocate(amb_matrix_sqrt(nmat,nmat),amb_matrix_sqrtm1(nmat,nmat))
 do t_kl=1,nmat
   amb_matrix_sqrt  (:,t_kl) = amb_matrix(:,t_kl)*SQRT(amb_eigval(t_kl))
   amb_matrix_sqrtm1(:,t_kl) = amb_matrix(:,t_kl)/SQRT(amb_eigval(t_kl))
 enddo
 deallocate(amb_eigval)

 amb_matrix = TRANSPOSE( amb_matrix )
 amb_matrix_sqrt  (:,:) = MATMUL( amb_matrix_sqrt(:,:)   , amb_matrix(:,:) )
 amb_matrix_sqrtm1(:,:) = MATMUL( amb_matrix_sqrtm1(:,:) , amb_matrix(:,:) )
 
 cc_matrix(:,:) = MATMUL( amb_matrix_sqrt , MATMUL( apb_matrix , amb_matrix_sqrt)  )

! WRITE_MASTER(*,*) 'CC ',matrix_is_symmetric(nmat,cc_matrix)


 WRITE_MASTER(*,'(a,i8,a,i8)') ' Diago (A - B)^{1/2} * (A + B) * (A - B)^{1/2}',nmat,' x ',nmat
 allocate(bigomega(nmat))
 call diagonalize(nmat,cc_matrix,bigomega)

 bigomega(:) = SQRT(bigomega(:))


 allocate(bigx(nmat,nmat),bigy(nmat,nmat))
 allocate(cc_matrix_bigomega(nmat,nmat))

 do t_kl=1,nmat
   cc_matrix_bigomega(:,t_kl) = cc_matrix(:,t_kl) * bigomega(t_kl)
   ! Resonant
   eigenvalue(t_kl)      =  bigomega(t_kl)
   ! AntiResonant
   eigenvalue(t_kl+nmat) = -bigomega(t_kl)
 enddo

 bigx(:,:) = 0.5_dp * MATMUL( amb_matrix_sqrt(:,:)   , cc_matrix(:,:) )
 bigy(:,:) = 0.5_dp * MATMUL( amb_matrix_sqrtm1(:,:) , cc_matrix_bigomega(:,:) )

 ! Resonant
 eigenvector(1:nmat       ,1:nmat)        = bigx(:,:)+bigy(:,:)
 eigenvector(nmat+1:2*nmat,1:nmat)        = bigx(:,:)-bigy(:,:)
 ! AntiResonant
 eigenvector(1:nmat       ,nmat+1:2*nmat) = bigx(:,:)-bigy(:,:)
 eigenvector(nmat+1:2*nmat,nmat+1:2*nmat) = bigx(:,:)+bigy(:,:)
 !
 ! Avoid inversion 
 eigenvector_inv(1:nmat       ,1:nmat)        = TRANSPOSE( bigx(:,:)+bigy(:,:) )
 eigenvector_inv(nmat+1:2*nmat,1:nmat)        = TRANSPOSE(-bigx(:,:)+bigy(:,:) )
 eigenvector_inv(1:nmat       ,nmat+1:2*nmat) = TRANSPOSE(-bigx(:,:)+bigy(:,:) )
 eigenvector_inv(nmat+1:2*nmat,nmat+1:2*nmat) = TRANSPOSE( bigx(:,:)+bigy(:,:) )

 ! Avoid inversion
! call start_clock(timing_inversion_s2p)
! call invert(npole,eigenvector_inv,eigenvector)
! call stop_clock(timing_inversion_s2p)

 !
 ! WARNING: I do not understand why I have to divide here to obtain the right
 !          normalization of the eigenvectors
 !          but it's working!
 ! TODO: do the analytic derivation
 do t_kl=1,2*nmat
   eigenvector(:,t_kl)     = eigenvector(:,t_kl)     / SQRT(ABS(eigenvalue(t_kl)))
   eigenvector_inv(t_kl,:) = eigenvector_inv(t_kl,:) / SQRT(ABS(eigenvalue(t_kl)))
 enddo


 deallocate(cc_matrix_bigomega)


 deallocate(amb_matrix_sqrt,amb_matrix_sqrtm1,bigomega)
 deallocate(bigx,bigy)
 deallocate(cc_matrix)

end subroutine diago_4blocks_sqrt


!=========================================================================
subroutine diago_4blocks_chol(nmat,amb_matrix,apb_matrix,npole,eigenvalue,eigenvector,eigenvector_inv)
 use m_spectral_function
 use m_eri
 use m_tools 
 implicit none

 integer,intent(in)                 :: nmat,npole
 real(dp),intent(inout)             :: amb_matrix(nmat,nmat),apb_matrix(nmat,nmat)
 real(dp),intent(out)               :: eigenvalue(npole)
 real(dp),intent(out)               :: eigenvector(npole,npole)
 real(dp),intent(out)               :: eigenvector_inv(npole,npole)
!=====
 integer  :: descm(ndel),desck(ndel)
 integer  :: descx(ndel),descy(ndel)
 integer  :: nlocal,mlocal
 integer  :: info
 integer  :: lwork
 real(dp),allocatable :: work(:)
!=====

#ifdef HAVE_SCALAPACK
 WRITE_MASTER(*,'(/,a)') ' Performing the block diago with Cholesky'
 call init_desc(nmat,descm,mlocal,nlocal)
 desck(:) = descm(:)
 call init_desc(2*nmat,descx,mlocal,nlocal)
 descy(:) = descx(:)

 allocate(work(1))
 lwork=-1
 call pdbssolver1_svd(nmat,apb_matrix,1,1,descm,amb_matrix,1,1,desck,            &
                      eigenvalue,eigenvector,1,1,descx,eigenvector_inv,1,1,descy,&
                      work,lwork,info)
 if(info/=0) stop'SCALAPACK failed'
 lwork=NINT(work(1))

 deallocate(work)
 allocate(work(lwork))
 call pdbssolver1_svd(nmat,apb_matrix,1,1,descm,amb_matrix,1,1,desck,            &
                      eigenvalue,eigenvector,1,1,descx,eigenvector_inv,1,1,descy,&
                      work,lwork,info)
 if(info/=0) stop'SCALAPACK failed'
 deallocate(work)

 !
 ! Need to transpose to be consistent with molgw
 eigenvector_inv = TRANSPOSE(eigenvector_inv)

#else
 stop'Cholesky diago cannot run without SCALAPACK'
#endif

end subroutine diago_4blocks_chol


!=========================================================================
subroutine polarizability_td(basis,prod_basis,auxil_basis,occupation,energy,c_matrix)
 use m_mpi
 use m_tools
 use m_basis_set
 use m_eri
 use m_dft_grid
 use m_spectral_function
 use m_gw
 implicit none

 type(basis_set),intent(in)            :: basis,prod_basis,auxil_basis
 real(dp),intent(in)                   :: occupation(basis%nbf,nspin)
 real(dp),intent(in)                   :: energy(basis%nbf,nspin),c_matrix(basis%nbf,basis%nbf,nspin)
!=====
 type(spectral_function) :: wpol_new,wpol_static
 integer                 :: kbf,ijspin,klspin
 integer                 :: istate,jstate,kstate,lstate
 integer                 :: ijstate_min
 integer                 :: ipole
 integer                 :: t_ij,t_kl

 real(dp),allocatable    :: eri_eigenstate_ijmin(:,:,:,:)
 real(dp)                :: eri_eigen_ijkl,eri_eigen_ikjl
 real(dp)                :: alpha_local,docc_ij,docc_kl
 real(dp),allocatable    :: h_2p(:,:)
 real(dp),allocatable    :: eigenvalue(:),eigenvector(:,:),eigenvector_inv(:,:)
 real(dp)                :: energy_qp(basis%nbf,nspin)

 real(dp),allocatable    :: v2rho2(:,:)
 real(dp),allocatable    :: vsigma(:,:)
 real(dp),allocatable    :: v2rhosigma(:,:)
 real(dp),allocatable    :: v2sigma2(:,:)
 real(dp),allocatable    :: wf_r(:,:,:)
 real(dp),allocatable    :: wf_gradr(:,:,:,:)
 real(dp),allocatable    :: rho_gradr(:,:,:)
 real(dp),allocatable    :: bra(:),ket(:)
 real(dp),allocatable    :: bra_auxil(:,:,:,:),ket_auxil(:,:,:,:)
 real(dp),allocatable    :: grad_ij(:,:,:),grad_kl(:,:,:)
 real(dp),allocatable    :: dot_ij_kl(:,:),dot_rho_ij(:,:),dot_rho_kl(:,:)

 logical                 :: is_tddft
 logical                 :: require_gradient
 logical                 :: is_ij
 logical                 :: is_rpa

!=====


 if( .NOT. calc_type%is_td .AND. .NOT. calc_type%is_bse) then
   stop'BUG: this should not happend in timedependent'
 endif
 WRITE_MASTER(*,'(/,a)') ' Calculating the polarizability for neutral excitation energies'

 call start_clock(timing_pola)
 
 inquire(file='manual_rpa',exist=is_rpa)
 if(is_rpa) then
   msg='RPA calculation is enforced'
   call issue_warning(msg)
 endif

 is_tddft = calc_type%is_td .AND. calc_type%is_dft .AND. .NOT. is_rpa

 ! Obtain the number of transition = the size of the matrix
 call init_spectral_function(basis%nbf,occupation,wpol_new)

 allocate(h_2p(wpol_new%npole,wpol_new%npole))
 allocate(eigenvector(wpol_new%npole,wpol_new%npole))
 allocate(eigenvalue(wpol_new%npole))

 if(calc_type%is_tda) then
   msg='Tamm-Dancoff approximation is switched on'
   call issue_warning(msg)
 endif

 if(calc_type%is_td) then
   alpha_local = alpha_hybrid
 else
   alpha_local = 1.0_dp
 endif

 !
 ! Prepare TDDFT calculations
 if(is_tddft) then
   call prepare_tddft(basis,c_matrix,occupation,v2rho2,vsigma,v2rhosigma,v2sigma2,wf_r,wf_gradr,rho_gradr)
   require_gradient = .FALSE.
   if(allocated(v2sigma2)) then ! GGA case
     require_gradient = .TRUE.
     allocate(grad_ij(3,ngrid,nspin))
     allocate(grad_kl(3,ngrid,nspin))
     allocate(dot_ij_kl(ngrid,nspin))
     allocate(dot_rho_ij(ngrid,nspin))
     allocate(dot_rho_kl(ngrid,nspin))
   endif
 endif

 !
 ! Prepare BSE calculations
 if( calc_type%is_bse .AND. .NOT.is_rpa ) then
   ! Set up energy_qp and wpol_static
   call prepare_bse(basis%nbf,energy,occupation,energy_qp,wpol_static)
 else
   ! For any other type of calculation, just fill energy_qp array with energy
   energy_qp(:,:) = energy(:,:)
 endif

 call start_clock(timing_build_h2p)

 WRITE_MASTER(*,*) 'Build the transition space matrix'
 !
 ! Prepare the bra and ket for BSE
 if(calc_type%is_bse .AND. .NOT.is_rpa) then

   allocate(bra(wpol_static%npole),ket(wpol_static%npole))

   if(is_auxil_basis) then
     allocate(bra_auxil(wpol_static%npole,ncore_W+1:nvirtual_W-1,ncore_W+1:nvirtual_W-1,nspin))
     allocate(ket_auxil(wpol_static%npole,ncore_W+1:nvirtual_W-1,ncore_W+1:nvirtual_W-1,nspin))
     do ijspin=1,nspin
       do istate=ncore_W+1,nvirtual_W-1 
         do jstate=ncore_W+1,nvirtual_W-1

           ! Here transform (sqrt(v) * chi * sqrt(v)) into  (v * chi * v)
           bra_auxil(:,istate,jstate,ijspin) = MATMUL( wpol_static%residu_left (:,:) , eri_3center_eigen(:,istate,jstate,ijspin) )
           ket_auxil(:,istate,jstate,ijspin) = MATMUL( wpol_static%residu_right(:,:) , eri_3center_eigen(:,istate,jstate,ijspin) )

         enddo
       enddo
     enddo
   endif
 endif


 if(.NOT. is_auxil_basis) then
   allocate(eri_eigenstate_ijmin(basis%nbf,basis%nbf,basis%nbf,nspin))
   ! Set this to zero and then enforce the calculation of the first array of Coulomb integrals
   eri_eigenstate_ijmin(:,:,:,:) = 0.0_dp
 endif



 h_2p(:,:)=0.0_dp

 do t_ij=1,wpol_new%npole
   istate = wpol_new%transition_table(1,t_ij)
   jstate = wpol_new%transition_table(2,t_ij)
   ijspin = wpol_new%transition_table(3,t_ij)
   docc_ij= occupation(istate,ijspin)-occupation(jstate,ijspin)

   if( .NOT. is_auxil_basis ) then
     ijstate_min = MIN(istate,jstate)
     is_ij = (ijstate_min == istate)
     call transform_eri_basis(nspin,c_matrix,ijstate_min,ijspin,eri_eigenstate_ijmin)
   endif


   do t_kl=1,wpol_new%npole
     kstate = wpol_new%transition_table(1,t_kl)
     lstate = wpol_new%transition_table(2,t_kl)
     klspin = wpol_new%transition_table(3,t_kl)
     docc_kl = occupation(kstate,klspin)-occupation(lstate,klspin)

     ! Tamm-Dancoff approximation: skip the coupling block 
     if( calc_type%is_tda .AND. docc_ij * docc_kl < 0.0_dp ) cycle

     if(is_auxil_basis) then
       eri_eigen_ijkl = eri_eigen_ri(istate,jstate,ijspin,kstate,lstate,klspin)
     else 
       if(is_ij) then ! treating (i,j)
         eri_eigen_ijkl = eri_eigenstate_ijmin(jstate,kstate,lstate,klspin)
       else           ! treating (j,i)
         eri_eigen_ijkl = eri_eigenstate_ijmin(istate,kstate,lstate,klspin)
       endif
     endif


     !
     ! Hartree part
     h_2p(t_ij,t_kl) = h_2p(t_ij,t_kl) + eri_eigen_ijkl * docc_ij

     !
     ! Add the kernel for TDDFT
     if(is_tddft) then
       if(nspin==1) then

         h_2p(t_ij,t_kl) = h_2p(t_ij,t_kl)   &
                    + SUM(  wf_r(:,istate,ijspin) * wf_r(:,jstate,ijspin) &
                          * wf_r(:,kstate,klspin) * wf_r(:,lstate,klspin) &
                          * v2rho2(:,ijspin) )                            & 
                          * docc_ij * 2.0_dp / spin_fact

         if(require_gradient) then
           grad_ij(1,:,ijspin) = wf_gradr(1,:,istate,ijspin) * wf_r(:,jstate,ijspin) + wf_gradr(1,:,jstate,ijspin) * wf_r(:,istate,ijspin)
           grad_ij(2,:,ijspin) = wf_gradr(2,:,istate,ijspin) * wf_r(:,jstate,ijspin) + wf_gradr(2,:,jstate,ijspin) * wf_r(:,istate,ijspin)
           grad_ij(3,:,ijspin) = wf_gradr(3,:,istate,ijspin) * wf_r(:,jstate,ijspin) + wf_gradr(3,:,jstate,ijspin) * wf_r(:,istate,ijspin)
           grad_kl(1,:,klspin) = wf_gradr(1,:,kstate,klspin) * wf_r(:,lstate,klspin) + wf_gradr(1,:,lstate,klspin) * wf_r(:,kstate,klspin)
           grad_kl(2,:,klspin) = wf_gradr(2,:,kstate,klspin) * wf_r(:,lstate,klspin) + wf_gradr(2,:,lstate,klspin) * wf_r(:,kstate,klspin)
           grad_kl(3,:,klspin) = wf_gradr(3,:,kstate,klspin) * wf_r(:,lstate,klspin) + wf_gradr(3,:,lstate,klspin) * wf_r(:,kstate,klspin)
           dot_ij_kl(:,ijspin) = grad_ij(1,:,ijspin) * grad_kl(1,:,klspin) + grad_ij(2,:,ijspin) * grad_kl(2,:,klspin) &
                                + grad_ij(3,:,ijspin) * grad_kl(3,:,klspin)
           dot_rho_ij(:,ijspin) = rho_gradr(1,:,1) * grad_ij(1,:,ijspin) + rho_gradr(2,:,1) * grad_ij(2,:,ijspin)  &
                                 + rho_gradr(3,:,1) * grad_ij(3,:,ijspin)
           dot_rho_kl(:,klspin) = rho_gradr(1,:,1) * grad_kl(1,:,klspin) + rho_gradr(2,:,1) * grad_kl(2,:,klspin)  &
                                 + rho_gradr(3,:,1) * grad_kl(3,:,klspin)

           h_2p(t_ij,t_kl) = h_2p(t_ij,t_kl)   &
                    + SUM( dot_ij_kl(:,1) * 3.0_dp * vsigma(:,1) ) * docc_ij / spin_fact
           h_2p(t_ij,t_kl) = h_2p(t_ij,t_kl)   &
                    + SUM( dot_rho_ij(:,1) * dot_rho_kl(:,1) * 4.5_dp * v2sigma2(:,1) ) * docc_ij / spin_fact
           h_2p(t_ij,t_kl) = h_2p(t_ij,t_kl)   &
                    + SUM( wf_r(:,istate,ijspin) * wf_r(:,jstate,ijspin) * dot_rho_kl(:,1) * 3.0_dp * v2rhosigma(:,1) ) * docc_ij / spin_fact
           h_2p(t_ij,t_kl) = h_2p(t_ij,t_kl)   &
                    + SUM( wf_r(:,kstate,klspin) * wf_r(:,lstate,klspin) * dot_rho_ij(:,1) * 3.0_dp * v2rhosigma(:,1) ) * docc_ij / spin_fact
         endif

       else

         h_2p(t_ij,t_kl) = h_2p(t_ij,t_kl)   &
                    + SUM(  wf_r(:,istate,ijspin) * wf_r(:,jstate,ijspin) &
                          * wf_r(:,kstate,klspin) * wf_r(:,lstate,klspin) &
                          * v2rho2(:,ijspin) )                            & 
                          * docc_ij  

         if(require_gradient) then
           stop'spin in TD-GGA not implemented yet'
         endif

       endif
     endif

     !
     ! Exchange part
     if( (calc_type%need_exchange .OR. calc_type%is_bse) .AND. .NOT.is_rpa ) then
       if(ijspin==klspin) then
         if(is_auxil_basis) then
           eri_eigen_ikjl = eri_eigen_ri(istate,kstate,ijspin,jstate,lstate,klspin)
         else
           if(is_ij) then
             eri_eigen_ikjl = eri_eigenstate_ijmin(kstate,jstate,lstate,klspin)
           else
             eri_eigen_ikjl = eri_eigenstate_ijmin(lstate,istate,kstate,klspin)
           endif
         endif

         h_2p(t_ij,t_kl) = h_2p(t_ij,t_kl) -  eri_eigen_ikjl  &
                           * docc_ij / spin_fact * alpha_local
       endif
     endif

     !
     ! Screened exchange part
     if(calc_type%is_bse .AND. .NOT.is_rpa ) then
       if(ijspin==klspin) then

         if(.NOT. is_auxil_basis) then
           kbf = prod_basis%index_prodbasis(istate,kstate)+prod_basis%nbf*(ijspin-1)
           bra(:) = wpol_static%residu_left (:,kbf)
           kbf = prod_basis%index_prodbasis(jstate,lstate)+prod_basis%nbf*(klspin-1)
           ket(:) = wpol_static%residu_right(:,kbf)
         else
           bra(:) = bra_auxil(:,istate,kstate,ijspin) 
           ket(:) = ket_auxil(:,jstate,lstate,klspin)
         endif

         h_2p(t_ij,t_kl) =  h_2p(t_ij,t_kl) -  SUM( bra(:)*ket(:)/(-wpol_static%pole(:)) ) &
                                                        * docc_ij / spin_fact   
       endif
     endif

   enddo ! t_kl


   h_2p(t_ij,t_ij) =  h_2p(t_ij,t_ij) + ( energy_qp(jstate,ijspin) - energy_qp(istate,ijspin) )


 enddo ! t_ij

 call destroy_spectral_function(wpol_static)

 if( .NOT. is_auxil_basis)               deallocate(eri_eigenstate_ijmin)
 if(is_tddft)                            deallocate(v2rho2,wf_r)
 if(calc_type%is_bse .AND. .NOT. is_rpa) deallocate(bra,ket)
 if(allocated(bra_auxil))                deallocate(bra_auxil)
 if(allocated(ket_auxil))                deallocate(ket_auxil)
 if(allocated(wf_gradr))                 deallocate(wf_gradr)

 call stop_clock(timing_build_h2p)

 WRITE_MASTER(*,*)
 WRITE_MASTER(*,*) 'diago 2-particle hamiltonian'
 WRITE_MASTER(*,*) 'matrix',wpol_new%npole,'x',wpol_new%npole

 call start_clock(timing_diago_h2p)
 call diagonalize_general(wpol_new%npole,h_2p,eigenvalue,eigenvector)
 call stop_clock(timing_diago_h2p)
 WRITE_MASTER(*,*) 'diago finished'
 WRITE_MASTER(*,*)
 deallocate(h_2p)
 allocate(eigenvector_inv(wpol_new%npole,wpol_new%npole))


 WRITE_MASTER(*,'(/,a,f14.8)') ' Lowest neutral excitation energy [eV]',MINVAL(ABS(eigenvalue(:)))*Ha_eV
   
 call start_clock(timing_inversion_s2p)
 call invert(wpol_new%npole,eigenvector,eigenvector_inv)
 call stop_clock(timing_inversion_s2p)

 !
 ! Calculate the optical sprectrum
 ! and the dynamic dipole tensor
 !
 call optical_spectrum(basis,prod_basis,occupation,c_matrix,wpol_new,eigenvector,eigenvector_inv,eigenvalue)

 !
 ! Calculate Wp= v * chi * v 
 ! and then write it down on file
 !
 if( print_specfunc ) then
  if( is_auxil_basis) then
    call chi_to_sqrtvchisqrtv_auxil(basis%nbf,auxil_basis%nbf,occupation,c_matrix,eigenvector,eigenvector_inv,eigenvalue,wpol_new)
  else
    call chi_to_vchiv(basis%nbf,prod_basis,occupation,c_matrix,eigenvector,eigenvector_inv,eigenvalue,wpol_new)
  endif
  call write_spectral_function(wpol_new)
  call destroy_spectral_function(wpol_new)
 endif

 if(allocated(eigenvector))     deallocate(eigenvector)
 if(allocated(eigenvector_inv)) deallocate(eigenvector_inv)
 if(allocated(eigenvalue))      deallocate(eigenvalue)

 call stop_clock(timing_pola)


end subroutine polarizability_td


!=========================================================================
subroutine optical_spectrum(basis,prod_basis,occupation,c_matrix,chi,eigenvector,eigenvector_inv,eigenvalue)
 use m_mpi
 use m_tools
 use m_basis_set
 use m_eri
 use m_dft_grid
 use m_spectral_function
 implicit none

 type(basis_set),intent(in)         :: basis,prod_basis
 real(dp),intent(in)                :: occupation(basis%nbf,nspin),c_matrix(basis%nbf,basis%nbf,nspin)
 type(spectral_function),intent(in) :: chi
 real(dp),intent(in)                :: eigenvector(chi%npole,chi%npole),eigenvector_inv(chi%npole,chi%npole)
 real(dp),intent(in)                :: eigenvalue(chi%npole)
!=====
 integer                            :: t_ij,t_kl
 integer                            :: istate,jstate,ijspin
 integer                            :: ibf,jbf
 integer                            :: ni,nj,li,lj,ni_cart,nj_cart,i_cart,j_cart,ibf_cart,jbf_cart
 integer                            :: iomega,idir,jdir
 integer,parameter                  :: nomega=600
 complex(dp)                        :: omega(nomega)
 real(dp)                           :: docc_ij
 real(dp)                           :: dynamical_pol(nomega,3,3),photoabsorp_cross(nomega,3,3)
 real(dp)                           :: static_polarizability(3,3)
 real(dp)                           :: oscillator_strength,trk_sumrule

 real(dp),allocatable               :: dipole_basis(:,:,:),dipole_state(:,:,:,:)
 real(dp),allocatable               :: dipole_cart(:,:,:)
 real(dp),allocatable               :: residu_left(:,:),residu_right(:,:)
 integer,parameter                  :: unit_dynpol=101
 integer,parameter                  :: unit_photocross=102
!=====

 call start_clock(timing_spectrum)
 !
 ! Calculate the spectrum now
 !

 WRITE_MASTER(*,'(/,a)') ' Calculate the optical spectrum'

 if (nspin/=1) stop'no nspin/=1 allowed'

 !
 ! First precalculate all the needed dipole in the basis set
 !
 allocate(dipole_basis(3,basis%nbf,basis%nbf))
 ibf_cart = 1
 ibf      = 1
 do while(ibf_cart<=basis%nbf_cart)
   li      = basis%bf(ibf_cart)%am
   ni_cart = number_basis_function_am(CARTESIAN,li)
   ni      = number_basis_function_am(basis%gaussian_type,li)

   jbf_cart = 1
   jbf      = 1
   do while(jbf_cart<=basis%nbf_cart)
     lj      = basis%bf(jbf_cart)%am
     nj_cart = number_basis_function_am(CARTESIAN,lj)
     nj      = number_basis_function_am(basis%gaussian_type,lj)

     allocate(dipole_cart(3,ni_cart,nj_cart))


     do i_cart=1,ni_cart
       do j_cart=1,nj_cart
         call basis_function_dipole(basis%bf(ibf_cart+i_cart-1),basis%bf(jbf_cart+j_cart-1),dipole_cart(:,i_cart,j_cart))
       enddo
     enddo

     do idir=1,3
       dipole_basis(idir,ibf:ibf+ni-1,jbf:jbf+nj-1) = MATMUL( TRANSPOSE( cart_to_pure(li)%matrix(:,:) ) , &
             MATMUL(  dipole_cart(idir,:,:) , cart_to_pure(lj)%matrix(:,:) ) )
     enddo

     deallocate(dipole_cart)

     jbf      = jbf      + nj
     jbf_cart = jbf_cart + nj_cart
   enddo

   ibf      = ibf      + ni
   ibf_cart = ibf_cart + ni_cart
 enddo

 !
 ! Get the dipole oscillator strength with states
 allocate(dipole_state(3,basis%nbf,basis%nbf,nspin))
 dipole_state(:,:,:,:) = 0.0_dp
 do ijspin=1,nspin
   do jbf=1,basis%nbf
     do ibf=1,basis%nbf
       do jstate=1,basis%nbf
         do istate=1,basis%nbf
           dipole_state(:,istate,jstate,ijspin) = dipole_state(:,istate,jstate,ijspin) &
                                         + c_matrix(ibf,istate,ijspin) * dipole_basis(:,ibf,jbf) * c_matrix(jbf,jstate,ijspin)
         enddo
       enddo
     enddo
   enddo
 enddo

 !
 ! Set the frequency mesh
 omega(1)     =MAX( 0.0_dp      ,MINVAL(ABS(eigenvalue(:)))-3.00/Ha_eV)
 omega(nomega)=MIN(20.0_dp/Ha_eV,MAXVAL(ABS(eigenvalue(:)))+3.00/Ha_eV)
 do iomega=2,nomega-1
   omega(iomega) = omega(1) + ( omega(nomega)-omega(1) ) /REAL(nomega-1,dp) * (iomega-1) 
 enddo
 ! Add the broadening
 omega(:) = omega(:) + im * 0.10/Ha_eV

 allocate(residu_left (3,chi%npole))
 allocate(residu_right(3,chi%npole))

 residu_left (:,:) = 0.0_dp
 residu_right(:,:) = 0.0_dp
 do t_ij=1,chi%npole
   istate = chi%transition_table(1,t_ij)
   jstate = chi%transition_table(2,t_ij)
   ijspin = chi%transition_table(3,t_ij)
   docc_ij = occupation(istate,ijspin)-occupation(jstate,ijspin)

   do t_kl=1,chi%npole
     residu_left (:,t_kl)  = residu_left (:,t_kl) &
                  + dipole_state(:,istate,jstate,ijspin) * eigenvector(t_ij,t_kl)
     residu_right(:,t_kl)  = residu_right(:,t_kl) &
                  + dipole_state(:,istate,Jstate,ijspin) * eigenvector_inv(t_kl,t_ij) &
                                   * docc_ij
   enddo

 enddo


 !
 ! Calculate the dynamical dipole polarizability
 ! and the static dipole polarizability
 dynamical_pol(:,:,:) = 0.0_dp
 static_polarizability(:,:) = 0.0_dp
 do t_ij=1,chi%npole
   do idir=1,3
     do jdir=1,3
       dynamical_pol(:,idir,jdir) = dynamical_pol(:,idir,jdir) &
                            + residu_left(idir,t_ij) * residu_right(jdir,t_ij) &
                              *AIMAG( -1.0_dp  / ( omega(:) - eigenvalue(t_ij) ) )
       static_polarizability(idir,jdir) = static_polarizability(idir,jdir) + residu_left(idir,t_ij) * residu_right(jdir,t_ij) / eigenvalue(t_ij)
     enddo
   enddo
 enddo
 !
 ! Get the photoabsorption cross section
 do iomega=1,nomega
   photoabsorp_cross(iomega,:,:) = 4.0_dp * pi * REAL(omega(iomega),dp) / c_speedlight * dynamical_pol(iomega,:,:)
 enddo

 WRITE_MASTER(*,'(/,a)') ' Neutral excitation energies [eV] and strengths'
 trk_sumrule=0.0_dp
 t_kl=0
 do t_ij=1,chi%npole
   if(eigenvalue(t_ij) > 0.0_dp) then
     t_kl = t_kl + 1
     oscillator_strength = 2.0_dp/3.0_dp * DOT_PRODUCT(residu_left(:,t_ij),residu_right(:,t_ij)) * eigenvalue(t_ij)
     trk_sumrule = trk_sumrule + oscillator_strength
     if(t_ij<30) then
       WRITE_MASTER(*,'(i4,10(f18.8,2x))') t_kl,eigenvalue(t_ij)*Ha_eV,oscillator_strength
     endif
   endif
 enddo
 WRITE_MASTER(*,*)
 WRITE_MASTER(*,*) 'TRK SUM RULE: the two following numbers should compare well'
 WRITE_MASTER(*,*) 'Sum over oscillator strengths',trk_sumrule
 WRITE_MASTER(*,*) 'Number of valence electrons  ',SUM( occupation(ncore_W+1:,:) )

 WRITE_MASTER(*,'(/,a)') ' Static dipole polarizability'
 do idir=1,3
   WRITE_MASTER(*,'(3(4x,f12.6))') static_polarizability(idir,:)
 enddo

 open(unit_dynpol,file='dynamical_dipole_polarizability.dat',form='formatted')
 open(unit_photocross,file='photoabsorption_cross_section.dat',form='formatted')
 WRITE_MASTER(unit_dynpol,'(a)') '#  Imaginary part of dynamical dipole polarizability'
 WRITE_MASTER(unit_dynpol,'(a)') '#  omega (eV)   Average     xx    yx    zx    xy    yy    zy    xz    yz    zz'
 WRITE_MASTER(unit_photocross,'(a)') '#  Imaginary part of dynamical dipole polarizability'
 WRITE_MASTER(unit_photocross,'(a)') '#  omega (eV)   Average     xx    yx    zx    xy    yy    zy    xz    yz    zz'
 do iomega=1,nomega
   WRITE_MASTER(unit_dynpol,'(11(e18.8,2x))') REAL(omega(iomega),dp)*Ha_eV,                                      &
                                              (dynamical_pol(iomega,1,1)+dynamical_pol(iomega,2,2)+dynamical_pol(iomega,3,3))/3.0_dp, &
                                              dynamical_pol(iomega,:,:)
   WRITE_MASTER(unit_photocross,'(11(e18.8,2x))') REAL(omega(iomega),dp)*Ha_eV,                                      &
                                                  (photoabsorp_cross(iomega,1,1)+photoabsorp_cross(iomega,2,2)+photoabsorp_cross(iomega,3,3))/3.0_dp, &
                                                  photoabsorp_cross(iomega,:,:)
 enddo 
 close(unit_dynpol)
 close(unit_photocross)


 deallocate(residu_left,residu_right)
 deallocate(dipole_state)

 call stop_clock(timing_spectrum)

end subroutine optical_spectrum


!=========================================================================
subroutine prepare_tddft(basis,c_matrix,occupation,v2rho2,vsigma,v2rhosigma,v2sigma2,wf_r,wf_gradr,rho_gradr)
 use m_dft_grid
 use m_basis_set
#ifdef HAVE_LIBXC
 use libxc_funcs_m
 use xc_f90_lib_m
 use xc_f90_types_m
#endif
 use iso_c_binding,only: C_INT,C_DOUBLE
 implicit none

 type(basis_set),intent(in)       :: basis
 real(dp),intent(in)              :: c_matrix(basis%nbf,basis%nbf,nspin)
 real(dp),intent(in)              :: occupation(basis%nbf,nspin)
 real(dp),allocatable,intent(out) :: v2rho2(:,:)
 real(dp),allocatable,intent(out) :: vsigma(:,:)
 real(dp),allocatable,intent(out) :: v2rhosigma(:,:)
 real(dp),allocatable,intent(out) :: v2sigma2(:,:)
 real(dp),allocatable,intent(out) :: wf_r(:,:,:)
 real(dp),allocatable,intent(out) :: wf_gradr(:,:,:,:)
 real(dp),allocatable,intent(out) :: rho_gradr(:,:,:)
!=====
 real(dp),parameter :: kernel_capping=1.0e14_dp
 integer  :: idft_xc,igrid
 integer  :: ispin
 real(dp) :: rr(3)
 real(dp) :: basis_function_r(basis%nbf)
 real(dp) :: basis_function_gradr(3,basis%nbf)
 real(dp) :: rhor_r(nspin)
 real(dp) :: grad_rhor(3,nspin)
 real(dp) :: p_matrix(basis%nbf,basis%nbf,nspin)
 logical  :: require_gradient
 character(len=256) :: string
#ifdef HAVE_LIBXC
 type(xc_f90_pointer_t) :: xc_func(ndft_xc),xc_functest
 type(xc_f90_pointer_t) :: xc_info(ndft_xc),xc_infotest
#endif
 real(C_DOUBLE) :: rho_c(nspin)
 real(C_DOUBLE) :: v2rho2_c(2*nspin-1)
 real(C_DOUBLE) :: sigma_c(2*nspin-1)
 real(C_DOUBLE) :: vrho_c(nspin)
 real(C_DOUBLE) :: vsigma_c(2*nspin-1)
 real(C_DOUBLE) :: v2rhosigma_c(5*nspin-4)
 real(C_DOUBLE) :: v2sigma2_c(5*nspin-4)
 real(dp)       :: max_v2sigma2
!=====

 !
 ! Prepare DFT kernel calculation with Libxc
 !
 require_gradient  =.FALSE.
 do idft_xc=1,ndft_xc
   if(nspin==1) then
     call xc_f90_func_init(xc_func(idft_xc), xc_info(idft_xc), dft_xc_type(idft_xc), XC_UNPOLARIZED)
   else
     call xc_f90_func_init(xc_func(idft_xc), xc_info(idft_xc), dft_xc_type(idft_xc), XC_POLARIZED)
   endif
   if( MODULO(xc_f90_info_flags( xc_info(idft_xc)),XC_FLAGS_HAVE_FXC*2) < XC_FLAGS_HAVE_FXC ) then
     stop'This functional does not have the kernel implemented in Libxc'
   endif
   call xc_f90_info_name(xc_info(idft_xc),string)
   WRITE_MASTER(*,'(a,i4,a,i6,5x,a)') '   XC functional ',idft_xc,' :  ',xc_f90_info_number(xc_info(idft_xc)),&
         TRIM(string)
   if(xc_f90_info_family(xc_info(idft_xc)) == XC_FAMILY_GGA     ) require_gradient  =.TRUE.
   if(xc_f90_info_family(xc_info(idft_xc)) == XC_FAMILY_HYB_GGA ) require_gradient  =.TRUE.
 enddo

 !
 ! calculate rho, grad rho and the kernel
 ! 
 ! Get the density matrix P from C
 call setup_density_matrix(basis%nbf,nspin,c_matrix,occupation,p_matrix)

 allocate(v2rho2(ngrid,nspin),wf_r(ngrid,basis%nbf,nspin))
 v2rho2(:,:) = 0.0_dp

 if(require_gradient) then
   allocate(vsigma(ngrid,2*nspin-1))
   allocate(v2rhosigma(ngrid,5*nspin-4))
   allocate(v2sigma2(ngrid,5*nspin-4))
   allocate(wf_gradr(3,ngrid,basis%nbf,nspin))
   allocate(rho_gradr(3,ngrid,nspin))
   vsigma(:,:)     = 0.0_dp
   v2rhosigma(:,:) = 0.0_dp
   v2sigma2(:,:)   = 0.0_dp
 endif


 max_v2sigma2 = -1.0_dp
 do igrid=1,ngrid

   rr(:) = rr_grid(:,igrid)

   if( .NOT. allocated(bfr) ) call prepare_basis_functions_r(basis)
   if( require_gradient .AND. .NOT. allocated(bfgr) ) call prepare_basis_functions_gradr(basis)
   !
   ! Get all the functions and gradients at point rr
   call get_basis_functions_r(basis,igrid,basis_function_r)
   !
   ! store the wavefunction in r
   do ispin=1,nspin
     wf_r(igrid,:,ispin) = MATMUL( basis_function_r(:) , c_matrix(:,:,ispin) )
   enddo

   if( require_gradient ) then
     call get_basis_functions_gradr(basis,igrid,basis_function_gradr)
     !
     ! store the wavefunction in r
     do ispin=1,nspin
       wf_gradr(:,igrid,:,ispin) = MATMUL( basis_function_gradr(:,:) , c_matrix(:,:,ispin) )
     enddo
   endif


   call calc_density_r(nspin,basis%nbf,p_matrix,basis_function_r,rhor_r)
   if( require_gradient ) then
     call calc_density_gradr(nspin,basis%nbf,p_matrix,basis_function_r,basis_function_gradr,grad_rhor)

     rho_gradr(:,igrid,:) = grad_rhor(:,:)

     sigma_c(1) = SUM( grad_rhor(:,1)**2 )
     if(nspin==2) then
       sigma_c(2) = SUM( grad_rhor(:,1) * grad_rhor(:,2) )
       sigma_c(3) = SUM( grad_rhor(:,2)**2 )
     endif

   endif


   rho_c(:) = rhor_r(:)

   !
   ! Calculate the kernel
   ! 
   do idft_xc=1,ndft_xc
     select case(xc_f90_info_family(xc_info(idft_xc)))
     case(XC_FAMILY_LDA)
       call xc_f90_lda_fxc(xc_func(idft_xc),1_C_INT,rho_c(1),v2rho2_c(1))
     case(XC_FAMILY_GGA,XC_FAMILY_HYB_GGA)
       call xc_f90_gga_vxc(xc_func(idft_xc),1_C_INT,rho_c(1),sigma_c(1),vrho_c(1),vsigma_c(1))
       call xc_f90_gga_fxc(xc_func(idft_xc),1_C_INT,rho_c(1),sigma_c(1),v2rho2_c(1),v2rhosigma_c(1),v2sigma2_c(1))
     case default
       stop'Other kernels not yet implemented'
     end select
     !
     ! Remove the too large values for stability
     v2rho2_c(:) = MIN( v2rho2_c(:), kernel_capping )
     if(require_gradient) then
       max_v2sigma2 = MAX(ABS(v2sigma2_c(1)),max_v2sigma2)
       vsigma_c(:)     = MIN( vsigma_c(:), kernel_capping )
       v2rhosigma_c(:) = MIN( v2rhosigma_c(:), kernel_capping )
       v2sigma2_c(:)   = MIN( v2sigma2_c(:), kernel_capping )
     endif

     ! Store the result with the weight
     ! Remove too large values for stability
     v2rho2(igrid,:)     = v2rho2(igrid,:) + v2rho2_c(:) * w_grid(igrid) * dft_xc_coef(idft_xc)
     if(require_gradient) then
       vsigma(igrid,:)     = vsigma(igrid,:)     + vsigma_c(:)     * w_grid(igrid) * dft_xc_coef(idft_xc)
       v2rhosigma(igrid,:) = v2rhosigma(igrid,:) + v2rhosigma_c(:) * w_grid(igrid) * dft_xc_coef(idft_xc)
       v2sigma2(igrid,:)   = v2sigma2(igrid,:)   + v2sigma2_c(:)   * w_grid(igrid) * dft_xc_coef(idft_xc)
     endif

   enddo
 enddo
 if(require_gradient) then
   WRITE_MASTER(*,'(a,e18.6)') ' Maximum numerical value for fxc: ',max_v2sigma2
 endif


end subroutine prepare_tddft


!=========================================================================
subroutine prepare_bse(nbf,energy,occupation,energy_qp,wpol_static)
 use m_dft_grid
 use m_spectral_function
 implicit none

 integer,intent(in)                  :: nbf
 real(dp),intent(in)                 :: energy(nbf,nspin)
 real(dp),intent(in)                 :: occupation(nbf,nspin)
 real(dp),intent(out)                :: energy_qp(nbf,nspin)
 type(spectral_function),intent(out) :: wpol_static
!=====
 integer  :: reading_status
 real(dp) :: scissor_energy(nspin)
 integer  :: ispin,istate
!=====

 ! For BSE calculation, obtain the wpol_static object from a previous calculation
 call read_spectral_function(wpol_static,reading_status)
 if(reading_status/=0) then
   stop'BSE requires a previous GW calculation stored in a spectral_file'
 endif

 call read_energy_qp(nspin,nbf,energy_qp,reading_status)
 select case(reading_status)
 case(-1)
   scissor_energy(:) = energy_qp(1,:)
   WRITE_MASTER(*,'(a,2(x,f12.6))') ' Scissor operator with value [eV]:',scissor_energy(:)*Ha_eV
   do ispin=1,nspin
     do istate=1,nbf
       if( occupation(istate,ispin) > completely_empty/spin_fact ) then
         energy_qp(istate,ispin) = energy(istate,ispin)
       else
         energy_qp(istate,ispin) = energy(istate,ispin) + scissor_energy(ispin)
       endif
     enddo
   enddo
   WRITE_MASTER(*,'(/,a)') ' Scissor updated energies'
   do istate=1,nbf
     WRITE_MASTER(*,'(i5,4(2x,f16.6))') istate,energy(istate,:)*Ha_eV,energy_qp(istate,:)*Ha_eV
   enddo
   WRITE_MASTER(*,*)
 case(0)
   WRITE_MASTER(*,'(a)') ' Reading OK'
 case(1,2)
   WRITE_MASTER(*,'(a,/,a)') ' Something happened during the reading of energy_qp file',' Fill up the QP energies with KS energies'
   energy_qp(:,:) = energy(:,:)
 case default
   stop'reading_status BUG'
 end select

end subroutine prepare_bse
!=========================================================================

end module m_timedependent
!=========================================================================