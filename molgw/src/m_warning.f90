!=========================================================================
#include "macros.h"
!=========================================================================
module m_warning
 use m_definitions
 use m_mpi


 integer,parameter          :: NWARNINGMAX=100
 integer,private            :: nwarning
 character(len=100),private :: warning_list(NWARNINGMAX)

 character(len=100)         :: msg
 

contains


!=========================================================================
subroutine init_warning()
 implicit none
 
 nwarning=0
 warning_list(:)=''

end subroutine init_warning


!=========================================================================
subroutine issue_warning(msgw)
 implicit none
 character(len=100),intent(in) :: msgw
!===== 
  
 WRITE_MASTER(*,'(/,a,a)') ' WARNING: ',TRIM(msgw)

 !
 ! Eliminate the storage of identical warnings
 if(ANY(warning_list(1:nwarning)==TRIM(msgw))) return

 nwarning = nwarning + 1
 warning_list(nwarning) = TRIM(msgw)

end subroutine issue_warning


!=========================================================================
subroutine output_all_warnings()
 implicit none
!=====
 integer :: iwarning
!=====

 if(nwarning>0) then
   WRITE_MASTER(*,'(/,a,/)') ' SUMMARY of all the WARNINGS issued during the run:'
   do iwarning=1,nwarning
     WRITE_MASTER(*,'(i2,a,5x,a)') iwarning,'.',warning_list(iwarning)
   enddo
   WRITE_MASTER(*,'(/)')
 endif

end subroutine output_all_warnings


!=========================================================================
end module m_warning
!=========================================================================
