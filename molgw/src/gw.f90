!=========================================================================
#include "macros.h"
!=========================================================================
subroutine gw_selfenergy(gwmethod,basis,prod_basis,occupation,energy,exchange_m_vxc_diag,c_matrix,s_matrix,wpol,selfenergy)
 use m_definitions
 use m_mpi
 use m_timing 
 use m_inputparam
 use m_warning,only: issue_warning,msg
 use m_basis_set
 use m_spectral_function
 use m_eri,only: eri_3center_eigen
 implicit none

 integer,intent(in)                 :: gwmethod
 type(basis_set)                    :: basis,prod_basis
 real(dp),intent(in)                :: occupation(basis%nbf,nspin),energy(basis%nbf,nspin),exchange_m_vxc_diag(basis%nbf,nspin)
 real(dp),intent(in)                :: c_matrix(basis%nbf,basis%nbf,nspin)
 real(dp),intent(in)                :: s_matrix(basis%nbf,basis%nbf)
 type(spectral_function),intent(in) :: wpol
 real(dp),intent(out)               :: selfenergy(basis%nbf,basis%nbf,nspin)
!=====
 logical               :: file_exists=.FALSE.
 integer               :: nomegai
 integer               :: iomegai
 real(dp),allocatable  :: omegai(:)
 real(dp),allocatable  :: selfenergy_omega(:,:,:,:)
 real(dp),allocatable  :: sigma_xc_m_vxc_diag(:)
 integer               :: bbf,ibf,kbf
 integer               :: astate,bstate
 integer               :: istate,ispin,ipole
 real(dp)              :: bra(wpol%npole_reso,basis%nbf)
 real(dp)              :: fact_full_r
 real(dp)              :: fact_empty_ar
 real(dp)              :: zz(nspin)
 real(dp)              :: energy_qp(basis%nbf,nspin)
 real(dp)              :: energy_qp_new(basis%nbf,nspin)
 real(dp)              :: energy_qp_z(nspin),energy_qp_omega(nspin)
 character(len=3)      :: ctmp
 integer               :: reading_status
!=====

 call start_clock(timing_self)


 WRITE_ME(msg,'(es9.2)') AIMAG(ieta)
 msg='small complex number is '//msg
 call issue_warning(msg)

 WRITE_MASTER(*,*)
 select case(gwmethod)
 case(QS)
   WRITE_MASTER(*,*) 'perform a QP self-consistent GW calculation'
 case(perturbative)
   WRITE_MASTER(*,*) 'perform a one-shot G0W0 calculation'
 case(COHSEX)
   WRITE_MASTER(*,*) 'perform a COHSEX calculation'
 case(QSCOHSEX)
   WRITE_MASTER(*,*) 'perform a self-consistent COHSEX calculation'
 case(GnW0)
   WRITE_MASTER(*,*) 'perform an eigenvalue self-consistent GnW0 calculation'
 case(GnWn)
   WRITE_MASTER(*,*) 'perform an eigenvalue self-consistent GnWn calculation'
 end select

 if(gwmethod==QS .OR. gwmethod==COHSEX .OR. gwmethod==QSCOHSEX .OR.  gwmethod==GnW0 .OR. gwmethod==GnWn) then
   nomegai = 0
   allocate(omegai(-nomegai:nomegai))
   omegai(0) = 0.0_dp
 else
   nomegai = nomega_sigma/2
   allocate(omegai(-nomegai:nomegai))
   do iomegai=-nomegai,nomegai
     omegai(iomegai) = step_sigma * iomegai
   enddo
 endif

 if( gwmethod==GnW0 .OR. gwmethod==GnWn ) then
   call read_energy_qp(nspin,basis%nbf,energy_qp,reading_status)
   if(reading_status/=0) then
     msg='File energy_qp not found: assuming 1st iteration'
     call issue_warning(msg)
     energy_qp(:,:) = energy(:,:)
   endif
 else
   energy_qp(:,:) = energy(:,:)
 endif

 allocate(selfenergy_omega(-nomegai:nomegai,basis%nbf,basis%nbf,nspin))
 selfenergy_omega(:,:,:,:) = 0.0_dp

 do ispin=1,nspin
   do istate=1,basis%nbf !INNER LOOP of G

     !
     ! Apply the frozen core and frozen virtual approximation to G
     if(istate <= ncore_G)    cycle
     if(istate >= nvirtual_G) cycle

     !
     ! Prepare the bra and ket with the knowledge of index istate and astate
     if( .NOT. has_auxil_basis) then
       ! Here just grab the precalculated value
       do astate=1,basis%nbf
         kbf = prod_basis%index_prodbasis(istate,astate) + prod_basis%nbf*(ispin-1)
         bra(:,astate) = wpol%residu_left(kbf,:)
       enddo
     else
       ! Here transform (sqrt(v) * chi * sqrt(v)) into  (v * chi * v)
       bra(:,:) = MATMUL( TRANSPOSE(wpol%residu_left(:,:)) , eri_3center_eigen(:,:,istate,ispin) )
     endif


     ! The application of residu theorem only retains the pole in certain
     ! quadrants.
     ! The positive poles of W go with the poles of occupied states in G
     ! The negative poles of W go with the poles of empty states in G
     fact_full_r   = occupation(istate,ispin) / spin_fact
     fact_empty_ar = (spin_fact - occupation(istate,ispin)) / spin_fact


     do ipole=1,wpol%npole_reso

       select case(gwmethod)
       case(QS)

         do bstate=1,basis%nbf
           do astate=1,basis%nbf

             selfenergy_omega(0,astate,bstate,ispin) = selfenergy_omega(0,astate,bstate,ispin) &
                        - bra(ipole,astate) * bra(ipole,bstate)                            &  
                          * ( REAL( -fact_full_r   / ( energy_qp(bstate,ispin) - ieta  - energy_qp(istate,ispin) + wpol%pole(ipole) ) , dp ) &
                             -REAL(  fact_empty_ar / ( energy_qp(bstate,ispin) + ieta  - energy_qp(istate,ispin) - wpol%pole(ipole) ) , dp ) )

           enddo
         enddo

       case(perturbative,GnW0,GnWn)

         do astate=1,basis%nbf
           !
           ! calculate only the diagonal !
           bstate=astate
!           do bstate=1,basis%nbf
             do iomegai=-nomegai,nomegai
               selfenergy_omega(iomegai,astate,bstate,ispin) = selfenergy_omega(iomegai,astate,bstate,ispin) &
                        - bra(ipole,astate) * bra(ipole,bstate)                                          & 
                          * ( REAL( -fact_full_r   / ( energy_qp(bstate,ispin) - ieta + omegai(iomegai) - energy_qp(istate,ispin) + wpol%pole(ipole) )  , dp )  &
                             -REAL(  fact_empty_ar / ( energy_qp(bstate,ispin) + ieta + omegai(iomegai) - energy_qp(istate,ispin) - wpol%pole(ipole) )  , dp ) )
             enddo
!           enddo
         enddo

       case(COHSEX,QSCOHSEX) 

         !
         ! SEX
         !
         do bstate=1,basis%nbf
           do astate=1,basis%nbf
             selfenergy_omega(0,astate,bstate,ispin) = selfenergy_omega(0,astate,bstate,ispin) &
                        - bra(ipole,astate) * bra(ipole,bstate)                            & 
                              * fact_full_r / (-wpol%pole(ipole))
           enddo
         enddo
         !
         ! COH
         !
         do bstate=1,basis%nbf
           do astate=1,basis%nbf
             selfenergy_omega(0,astate,bstate,ispin) = selfenergy_omega(0,astate,bstate,ispin) &
                        - bra(ipole,astate) * bra(ipole,bstate) & 
                              * fact_empty_ar / wpol%pole(ipole)
           enddo
         enddo

       case default 
         stop'BUG'
       end select

     enddo !ipole

   enddo !istate
 enddo !ispin

 !
 ! Kotani's Hermitianization trick
 !
 if(gwmethod==QS) then
   do ispin=1,nspin
     selfenergy_omega(0,:,:,ispin) = 0.5_dp * ( selfenergy_omega(0,:,:,ispin) + TRANSPOSE(selfenergy_omega(0,:,:,ispin)) )
   enddo
 endif

 select case(gwmethod)
 case(QS)
   ! Transform the matrix elements back to the AO basis
   ! do not forget the overlap matrix S
   ! C^T S C = I
   ! the inverse of C is C^T S
   ! the inverse of C^T is S C
   do ispin=1,nspin
     selfenergy(:,:,ispin) = MATMUL( MATMUL( s_matrix(:,:) , c_matrix(:,:,ispin) ) , MATMUL( selfenergy_omega(0,:,:,ispin), &
                             MATMUL( TRANSPOSE(c_matrix(:,:,ispin)), s_matrix(:,:) ) ) )
   enddo


 case(QSCOHSEX)
   ! Transform the matrix elements back to the AO basis
   ! do not forget the overlap matrix S
   ! C^T S C = I
   ! the inverse of C is C^T S
   ! the inverse of C^T is S C
   do ispin=1,nspin
     selfenergy(:,:,ispin) = MATMUL( MATMUL( s_matrix(:,:) , c_matrix(:,:,ispin)) , MATMUL( selfenergy_omega(0,:,:,ispin), &
                             MATMUL( TRANSPOSE(c_matrix(:,:,ispin)), s_matrix(:,:) ) ) )
   enddo


 case(COHSEX) !==========================================================

   selfenergy(:,:,:) = selfenergy_omega(0,:,:,:)
   
   WRITE_MASTER(*,'(/,a)') ' COHSEX Eigenvalues [eV]'
   if(nspin==1) then
     WRITE_MASTER(*,*) '  #          E0        SigX-Vxc      SigC          Z         G0W0'
   else
     WRITE_MASTER(*,'(a)') '  #                E0                      SigX-Vxc                    SigC                       Z                       G0W0'
   endif
   do astate=1,basis%nbf
     zz(:) = 1.0_dp 
     energy_qp_new(astate,:) = energy_qp(astate,:) + selfenergy_omega(0,astate,astate,:) + exchange_m_vxc_diag(astate,:)

     WRITE_MASTER(*,'(i4,x,20(x,f12.6))') astate,energy_qp(astate,:)*Ha_eV,               &
                                                 exchange_m_vxc_diag(astate,:)*Ha_eV,     &
                                                 selfenergy_omega(0,astate,astate,:)*Ha_eV, &
                                           zz(:),energy_qp_new(astate,:)*Ha_eV
   enddo

   call write_energy_qp(nspin,basis%nbf,energy_qp_new)


 case(perturbative) !==========================================================

   if(print_sigma_) then

     do astate=1,basis%nbf
       WRITE_ME(ctmp,'(i3.3)') astate
       open(200+astate,file='selfenergy_omega_state'//TRIM(ctmp))
       WRITE_MASTER(200+astate,'(a)') '# omega + e_KS (eV)     SigmaC (eV)    omega + e_KS - Vxc + SigmaX (eV)     A (eV^-1) '
       do iomegai=-nomegai,nomegai
         WRITE_MASTER(200+astate,'(20(f12.6,2x))') ( omegai(iomegai) + energy_qp(astate,:) )*Ha_eV,               &
                                                   selfenergy_omega(iomegai,astate,astate,:)*Ha_eV,                 &
                                                   ( omegai(iomegai) - exchange_m_vxc_diag(astate,:) )*Ha_eV,     &
                                                   1.0_dp/pi/ABS( omegai(iomegai) - exchange_m_vxc_diag(astate,:) &
                                                           - selfenergy_omega(iomegai,astate,astate,:) ) / Ha_eV
       enddo
       WRITE_MASTER(200+astate,*)
     enddo
     close(200+astate)

   endif



   selfenergy(:,:,:) = selfenergy_omega(0,:,:,:)

   WRITE_MASTER(*,'(/,a)') ' G0W0 Eigenvalues [eV]'
   if(nspin==1) then
     WRITE_MASTER(*,*) '  #          E0        SigX-Vxc      SigC          Z         G0W0_Z         G0W0_qp'
   else
     WRITE_MASTER(*,'(a)') &
       '  #                E0                      SigX-Vxc                    SigC                       Z                       G0W0_Z                      G0W0_qp'
   endif
   do astate=1,basis%nbf
     zz(:) = ( selfenergy_omega(1,astate,astate,:) - selfenergy_omega(-1,astate,astate,:) ) / ( omegai(1) - omegai(-1) )
     zz(:) = 1.0_dp / ( 1.0_dp - zz(:) )
     ! Contrain Z to be in [0:1] to avoid crazy values
     do ispin=1,nspin
       zz(ispin) = MIN( MAX(zz(ispin),0.0_dp) , 1.0_dp )
     enddo

     energy_qp_z(:) = energy_qp(astate,:) + zz(:) * ( selfenergy_omega(0,astate,astate,:) + exchange_m_vxc_diag(astate,:) )

     allocate(sigma_xc_m_vxc_diag(-nomegai:nomegai))
     do ispin=1,nspin
       sigma_xc_m_vxc_diag(:) = selfenergy_omega(:,astate,astate,ispin) + exchange_m_vxc_diag(astate,ispin)
       energy_qp_omega(ispin) = find_fixed_point(nomegai,omegai,sigma_xc_m_vxc_diag) & 
                                 + energy_qp(astate,ispin) + exchange_m_vxc_diag(astate,ispin)
     enddo
     deallocate(sigma_xc_m_vxc_diag)



     WRITE_MASTER(*,'(i4,x,20(x,f12.6))') astate,energy_qp(astate,:)*Ha_eV,                 & 
                                                 exchange_m_vxc_diag(astate,:)*Ha_eV,       &
                                                 selfenergy_omega(0,astate,astate,:)*Ha_eV, &
                                                 zz(:),                                     & 
                                                 energy_qp_z(:)*Ha_eV,                      &
                                                 energy_qp_omega(:)*Ha_eV

     energy_qp_new(astate,:) = energy_qp_omega(:) 
   enddo

   call write_energy_qp(nspin,basis%nbf,energy_qp_new)



 case(GnW0,GnWn) !==========================================================

     selfenergy(:,:,:) = selfenergy_omega(0,:,:,:)

     WRITE_MASTER(*,'(/,a)') ' GnW0 Eigenvalues [eV]'
     if(nspin==1) then
       WRITE_MASTER(*,'(a)') '  #          E0        SigX-Vxc      SigC          Z          GW(n-1)       GW(n)'
     else
       WRITE_MASTER(*,'(a)') '  #                E0                      SigX-Vxc                    SigC                       Z                       G0W0'
     endif
     do astate=1,basis%nbf
       zz(:) = 1.0_dp 

       energy_qp_new(astate,:) = energy(astate,:) + selfenergy_omega(0,astate,astate,:) + exchange_m_vxc_diag(astate,:)

       WRITE_MASTER(*,'(i4,x,20(x,f12.6))') astate,energy(astate,:)*Ha_eV,                    &
                                                   exchange_m_vxc_diag(astate,:)*Ha_eV,       &
                                                   selfenergy_omega(0,astate,astate,:)*Ha_eV, &
                                                   zz(:),                                     &
                                                   energy_qp(astate,:)*Ha_eV,                 &
                                                   energy_qp_new(astate,:)*Ha_eV
     enddo

     call write_energy_qp(nspin,basis%nbf,energy_qp_new)

 end select


 deallocate(omegai)
 deallocate(selfenergy_omega)

 call stop_clock(timing_self)


contains


function find_fixed_point(nx,xx,fx) result(fixed_point)
 implicit none
 integer,intent(in)  :: nx
 real(dp),intent(in) :: xx(-nx:nx)
 real(dp),intent(in) :: fx(-nx:nx)
 real(dp)            :: fixed_point
!=====
 integer             :: ix,imin
 real(dp)            :: rmin
 real(dp)            :: gx(-nx:nx)
 real(dp)            :: gpx
!=====


 gx(:) = fx(:) - xx(:)

 rmin = HUGE(1.0_dp)
 do ix=-nx,nx
   if( ABS(gx(ix)) < rmin ) then
     rmin = ABS(gx(ix))
     imin = ix
   endif
 enddo

!FBFB write(*,*) imin
!FBFB write(*,*) rmin
!FBFB write(*,*) -nx,nx
!FBFB write(*,*) gx(-nx)*Ha_eV,gx(nx)*Ha_eV
!FBFB write(*,*) fx(-nx)*Ha_eV,fx(nx)*Ha_eV
!FBFB write(*,*) xx(-nx)*Ha_eV,xx(nx)*Ha_eV
!FBFB write(*,*) 
!FBFB write(*,*) imin-1,xx(imin-1)*Ha_eV,fx(imin-1)*Ha_eV,ABS(gx(imin-1))*Ha_eV
!FBFB write(*,*) imin  ,xx(imin)*Ha_eV  ,fx(imin)*Ha_eV  ,ABS(gx(imin))*Ha_eV
!FBFB write(*,*) imin+1,xx(imin+1)*Ha_eV,fx(imin+1)*Ha_eV,ABS(gx(imin+1))*Ha_eV
!FBFB write(*,*) 

 if( imin == -nx .OR. imin == nx) then
   fixed_point = xx(imin)
 else 
   if( gx(imin)*gx(imin+1) < 0.0_dp )  then
     gpx = ( gx(imin+1) - gx(imin) ) / ( xx(imin+1) - xx(imin) )
     fixed_point = xx(imin) - gx(imin) / gpx 
   else if( gx(imin)*gx(imin-1) < 0.0_dp )  then
     gpx = ( gx(imin) - gx(imin-1) ) / ( xx(imin) - xx(imin-1) )
     fixed_point = xx(imin) - gx(imin) / gpx 
   else
     fixed_point = xx(imin)
   endif
 endif

!FBFB write(*,*) fixed_point*Ha_eV


end function find_fixed_point


end subroutine gw_selfenergy


!=========================================================================
