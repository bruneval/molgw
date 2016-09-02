!=========================================================================
! This file is part of MOLGW.
! Author: Fabien Bruneval
!
! This file contains
! the perturbation theory to 2nd order evaluation of the self-energy
!
!=========================================================================
subroutine pt2_selfenergy(nstate,basis,occupation,energy,c_matrix,s_matrix,selfenergy_omega,emp2)
 use m_definitions
 use m_mpi
 use m_warning
 use m_basis_set
 use m_eri_ao_mo
 use m_inputparam
 use m_spectral_function
 use m_selfenergy_tools
 implicit none

 integer,intent(in)         :: nstate
 type(basis_set),intent(in) :: basis
 real(dp),intent(in)        :: occupation(nstate,nspin),energy(nstate,nspin)
 real(dp),intent(in)        :: c_matrix(basis%nbf,nstate,nspin)
 real(dp),intent(in)        :: s_matrix(basis%nbf,basis%nbf)
 real(dp),intent(out)       :: selfenergy_omega(-nomegai:nomegai,nsemin:nsemax,nspin)
 real(dp),intent(out)       :: emp2
!=====
 integer               :: astate,bstate
 real(dp),allocatable  :: selfenergy_ring(:,:,:)
 real(dp),allocatable  :: selfenergy_sox(:,:,:)
 real(dp),allocatable  :: selfenergy_output(:,:,:)
 real(dp),allocatable  :: zz(:,:)
 real(dp),allocatable  :: selfenergy_final(:,:)
 integer               :: iomegai
 integer               :: istate,jstate,kstate
 integer               :: abispin,jkspin
 real(dp)              :: fact_occ1,fact_occ2
 real(dp)              :: fi,fj,fk,ei,ej,ek
 real(dp)              :: omega
 real(dp)              :: fact_real,fact_energy
 real(dp)              :: emp2_sox,emp2_ring
 real(dp),allocatable  :: eri_eigenstate_i(:,:,:,:)
 integer               :: reading_status
 real(dp)              :: coul_ibjk,coul_ijkb,coul_iakj
 real(dp)              :: energy_qp_z(nstate,nspin)
 real(dp)              :: energy_qp_new(nstate,nspin)
!=====

 call start_clock(timing_mp2_self)

 emp2_ring = 0.0_dp
 emp2_sox  = 0.0_dp

 write(msg,'(es9.2)') AIMAG(ieta)
 call issue_warning('small complex number is '//msg)


 write(stdout,'(/,a)') ' Perform the second-order self-energy calculation'
 write(stdout,*) 'with the perturbative approach'

 

 if(has_auxil_basis) then
   call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix,ncore_G+1,nvirtual_G-1,ncore_G+1,nvirtual_G-1)
 else
   allocate(eri_eigenstate_i(nstate,nstate,nstate,nspin))
 endif



 allocate(selfenergy_ring(-nomegai:nomegai,nsemin:nsemax,nspin))
 allocate(selfenergy_sox (-nomegai:nomegai,nsemin:nsemax,nspin))


 selfenergy_ring(:,:,:) = 0.0_dp
 selfenergy_sox(:,:,:)  = 0.0_dp

 do abispin=1,nspin
   do istate=ncore_G+1,nvirtual_G-1 !LOOP of the first Green's function
     if( MODULO( istate - (ncore_G+1) , nproc_ortho ) /= rank_ortho ) cycle

     if( .NOT. has_auxil_basis ) then
       call calculate_eri_4center_eigen(basis%nbf,nstate,c_matrix,istate,abispin,eri_eigenstate_i)
     endif

     fi = occupation(istate,abispin)
     ei = energy(istate,abispin)

     do astate=nsemin,nsemax ! external loop ( bra )
       bstate=astate         ! external loop ( ket )


       do jkspin=1,nspin
         do jstate=ncore_G+1,nvirtual_G-1  !LOOP of the second Green's function
           fj = occupation(jstate,jkspin)
           ej = energy(jstate,jkspin)

           do kstate=ncore_G+1,nvirtual_G-1 !LOOP of the third Green's function
             fk = occupation(kstate,jkspin)
             ek = energy(kstate,jkspin)

             fact_occ1 = (spin_fact-fi) *            fj  * (spin_fact-fk) / spin_fact**3
             fact_occ2 =            fi  * (spin_fact-fj) *            fk  / spin_fact**3

             if( fact_occ1 < completely_empty .AND. fact_occ2 < completely_empty ) cycle

             if( has_auxil_basis ) then
               coul_iakj = eri_eigen_ri(istate,astate,abispin,kstate,jstate,jkspin)
               coul_ibjk = eri_eigen_ri(istate,bstate,abispin,jstate,kstate,jkspin)
               if( abispin == jkspin ) then
                 coul_ijkb = eri_eigen_ri(istate,jstate,abispin,kstate,bstate,abispin) 
               endif
             else
               coul_iakj = eri_eigenstate_i(astate,kstate,jstate,jkspin)
               coul_ibjk = eri_eigenstate_i(bstate,jstate,kstate,jkspin)
               if( abispin == jkspin ) then
                 coul_ijkb = eri_eigenstate_i(jstate,kstate,bstate,abispin) 
               endif
             endif

             do iomegai=-nomegai,nomegai
               omega = energy(bstate,abispin) + omegai(iomegai)

               fact_real   = REAL( fact_occ1 / (omega-ei+ej-ek+ieta) + fact_occ2 / (omega-ei+ej-ek-ieta) , dp)
               fact_energy = REAL( fact_occ1 / (energy(astate,abispin)-ei+ej-ek+ieta) , dp )

               selfenergy_ring(iomegai,astate,abispin) = selfenergy_ring(iomegai,astate,abispin) &
                        + fact_real * coul_iakj * coul_ibjk * spin_fact

               if(iomegai==0 .AND. astate==bstate .AND. occupation(astate,abispin)>completely_empty) then
                 emp2_ring = emp2_ring + occupation(astate,abispin) &
                                       * fact_energy * coul_iakj * coul_ibjk * spin_fact
               endif

               if( abispin == jkspin ) then

                 selfenergy_sox(iomegai,astate,abispin) = selfenergy_sox(iomegai,astate,abispin) &
                          - fact_real * coul_iakj * coul_ijkb

                 if(iomegai==0 .AND. astate==bstate .AND. occupation(astate,abispin)>completely_empty) then
                   emp2_sox = emp2_sox - occupation(astate,abispin) &
                             * fact_energy * coul_iakj * coul_ijkb
                 endif

               endif
  
  
             enddo ! iomega
  
           enddo
         enddo
       enddo 
     enddo
   enddo 
 enddo ! abispin

 call xsum_ortho(selfenergy_ring)
 call xsum_ortho(selfenergy_sox)
 call xsum_ortho(emp2_ring)
 call xsum_ortho(emp2_sox)

 emp2_ring = 0.5_dp * emp2_ring
 emp2_sox  = 0.5_dp * emp2_sox
 if( nsemin <= ncore_G+1 .AND. nsemax >= nhomo_G ) then
   emp2 = emp2_ring + emp2_sox
   write(stdout,'(/,a)')       ' MP2 Energy'
   write(stdout,'(a,f14.8)')   ' 2-ring diagram  :',emp2_ring
   write(stdout,'(a,f14.8)')   ' SOX diagram     :',emp2_sox
   write(stdout,'(a,f14.8,/)') ' MP2 correlation :',emp2
 else
   emp2 = 0.0_dp
 endif

 selfenergy_omega(:,:,:) = selfenergy_ring(:,:,:) + selfenergy_sox(:,:,:)


 if( ALLOCATED(eri_eigenstate_i) ) deallocate(eri_eigenstate_i)
 deallocate(selfenergy_ring)
 deallocate(selfenergy_sox)
 if(has_auxil_basis) call destroy_eri_3center_eigen()

 call stop_clock(timing_mp2_self)

end subroutine pt2_selfenergy


!=========================================================================
subroutine pt2_selfenergy_qs(nstate,basis,occupation,energy,c_matrix,s_matrix,selfenergy,emp2)
 use m_definitions
 use m_mpi
 use m_warning
 use m_basis_set
 use m_eri_ao_mo
 use m_inputparam
 use m_spectral_function
 use m_selfenergy_tools
 implicit none

 integer,intent(in)         :: nstate
 type(basis_set),intent(in) :: basis
 real(dp),intent(in)        :: occupation(nstate,nspin),energy(nstate,nspin)
 real(dp),intent(in)        :: c_matrix(basis%nbf,nstate,nspin)
 real(dp),intent(in)        :: s_matrix(basis%nbf,basis%nbf)
 real(dp),intent(out)       :: selfenergy(basis%nbf,basis%nbf,nspin)
 real(dp),intent(out)       :: emp2
!=====
 integer               :: astate,bstate,bstate2
 real(dp),allocatable  :: selfenergy_ring(:,:,:)
 real(dp),allocatable  :: selfenergy_sox(:,:,:)
 real(dp),allocatable  :: selfenergy_output(:,:,:)
 integer               :: istate,jstate,kstate
 integer               :: abispin,jkspin
 real(dp)              :: fact_occ1,fact_occ2
 real(dp)              :: fi,fj,fk,ei,ej,ek,ea,eb
 real(dp)              :: fact_real,fact_energy
 real(dp)              :: emp2_sox,emp2_ring
 real(dp),allocatable  :: eri_eigenstate_i(:,:,:,:)
 integer               :: reading_status
 real(dp)              :: coul_ibjk,coul_ijkb,coul_iakj
 real(dp)              :: energy_qp_z(nstate,nspin)
 real(dp)              :: energy_qp_new(nstate,nspin)
!=====

 call start_clock(timing_mp2_self)

 emp2_ring = 0.0_dp
 emp2_sox  = 0.0_dp

 write(msg,'(es9.2)') AIMAG(ieta)
 call issue_warning('small complex number is '//msg)


 write(stdout,'(/,a)') ' Perform the second-order self-energy calculation'
 write(stdout,*) 'with the QP self-consistent approach'

 

 if(has_auxil_basis) then
   call calculate_eri_3center_eigen(basis%nbf,nstate,c_matrix,ncore_G+1,nvirtual_G-1,ncore_G+1,nvirtual_G-1)
 else
   allocate(eri_eigenstate_i(nstate,nstate,nstate,nspin))
 endif



 allocate(selfenergy_ring (nsemin:nsemax,nsemin:nsemax,nspin))
 allocate(selfenergy_sox  (nsemin:nsemax,nsemin:nsemax,nspin))


 selfenergy_ring(:,:,:) = 0.0_dp
 selfenergy_sox(:,:,:)  = 0.0_dp

 do abispin=1,nspin
   do istate=ncore_G+1,nvirtual_G-1 !LOOP of the first Green's function
     if( MODULO( istate - (ncore_G+1) , nproc_ortho ) /= rank_ortho ) cycle

     if( .NOT. has_auxil_basis ) then
       call calculate_eri_4center_eigen(basis%nbf,nstate,c_matrix,istate,abispin,eri_eigenstate_i)
     endif

     fi = occupation(istate,abispin)
     ei = energy(istate,abispin)

     do astate=nsemin,nsemax ! external loop ( bra )
       do bstate=nsemin,nsemax   ! external loop ( ket )
         if( astate /= bstate .AND. calc_type%selfenergy_technique == one_shot ) cycle
         if( calc_type%selfenergy_technique == one_shot ) then
           bstate2 = 1
         else
           bstate2 = bstate
         endif

         do jkspin=1,nspin
           do jstate=ncore_G+1,nvirtual_G-1  !LOOP of the second Green's function
             fj = occupation(jstate,jkspin)
             ej = energy(jstate,jkspin)
  
             do kstate=ncore_G+1,nvirtual_G-1 !LOOP of the third Green's function
               fk = occupation(kstate,jkspin)
               ek = energy(kstate,jkspin)
  
               fact_occ1 = (spin_fact-fi) *            fj  * (spin_fact-fk) / spin_fact**3
               fact_occ2 =            fi  * (spin_fact-fj) *            fk  / spin_fact**3
  
               if( fact_occ1 < completely_empty .AND. fact_occ2 < completely_empty ) cycle

               if( has_auxil_basis ) then
                 coul_iakj = eri_eigen_ri(istate,astate,abispin,kstate,jstate,jkspin)
                 coul_ibjk = eri_eigen_ri(istate,bstate,abispin,jstate,kstate,jkspin)
                 if( abispin == jkspin ) then
                   coul_ijkb = eri_eigen_ri(istate,jstate,abispin,kstate,bstate,abispin) 
                 endif
               else
                 coul_iakj = eri_eigenstate_i(astate,kstate,jstate,jkspin)
                 coul_ibjk = eri_eigenstate_i(bstate,jstate,kstate,jkspin)
                 if( abispin == jkspin ) then
                   coul_ijkb = eri_eigenstate_i(jstate,kstate,bstate,abispin) 
                 endif
               endif

               ea = energy(astate,abispin) 
               eb = energy(bstate,abispin) 
  
               fact_real   = REAL( fact_occ1 / (eb-ei+ej-ek+ieta) + fact_occ2 / (eb-ei+ej-ek-ieta) , dp)
               fact_energy = REAL( fact_occ1 / (ea-ei+ej-ek+ieta) , dp )
  
               selfenergy_ring(astate,bstate2,abispin) = selfenergy_ring(astate,bstate2,abispin) &
                        + fact_real * coul_iakj * coul_ibjk * spin_fact

               if(astate==bstate .AND. occupation(astate,abispin)>completely_empty) then
                 emp2_ring = emp2_ring + occupation(astate,abispin) &
                                       * fact_energy * coul_iakj * coul_ibjk * spin_fact
               endif
 
               if( abispin == jkspin ) then

                 selfenergy_sox(astate,bstate2,abispin) = selfenergy_sox(astate,bstate2,abispin) &
                          - fact_real * coul_iakj * coul_ijkb

                 if(astate==bstate .AND. occupation(astate,abispin)>completely_empty) then
                   emp2_sox = emp2_sox - occupation(astate,abispin) &
                             * fact_energy * coul_iakj * coul_ijkb
                 endif

               endif
    
    
    
             enddo
           enddo
         enddo
       enddo 
     enddo
   enddo 
 enddo ! abispin

 call xsum_ortho(selfenergy_ring)
 call xsum_ortho(selfenergy_sox)
 call xsum_ortho(emp2_ring)
 call xsum_ortho(emp2_sox)

 emp2_ring = 0.5_dp * emp2_ring
 emp2_sox  = 0.5_dp * emp2_sox
 if( nsemin <= ncore_G+1 .AND. nsemax >= nhomo_G ) then
   emp2 = emp2_ring + emp2_sox
   write(stdout,'(/,a)')       ' MP2 Energy'
   write(stdout,'(a,f14.8)')   ' 2-ring diagram  :',emp2_ring
   write(stdout,'(a,f14.8)')   ' SOX diagram     :',emp2_sox
   write(stdout,'(a,f14.8,/)') ' MP2 correlation :',emp2
 else
   emp2 = 0.0_dp
 endif


 selfenergy(:,:,:) = selfenergy_ring(:,:,:) + selfenergy_sox(:,:,:)

 call apply_qs_approximation(basis%nbf,nstate,s_matrix,c_matrix,selfenergy)


 if( ALLOCATED(eri_eigenstate_i) ) deallocate(eri_eigenstate_i)
 deallocate(selfenergy_ring)
 deallocate(selfenergy_sox)
 if(has_auxil_basis) call destroy_eri_3center_eigen()

 call stop_clock(timing_mp2_self)

end subroutine pt2_selfenergy_qs


!=========================================================================