subroutine init_wings ( fname, wings )
  !---------------------------------------------------
  ! initializes an array of wings. the initial state is always
  ! straight lines, possible oriented with different angles, at rest.
  !---------------------------------------------------
  implicit none
  integer :: n, i, a, j, ind, itri
  character(len=strlen), intent(in) :: fname
  type(flexible_wing), dimension (1:nWings), intent (inout) :: Wings
  real(kind=pr) :: alpha
  real(kind=pr) :: delta(1:3)
  real(kind=pr), allocatable :: normal(:,:)

  type(inifile) :: PARAMS
  ! LeadingEdge: x, y, vx, vy, ax, ay (Array)
  !real (kind=pr), dimension(1:6) :: LeadingEdge
  character(len=1)  :: wingstr
  character(len=16) :: frmt


  if (root) then
    write(*,'(80("<"))')
    write(*,*) "Initializing flexible wing module!"
    write(*,*) "*.ini file is: "//trim(adjustl(fname))
    write(*,'(80("<"))')
  endif


  !-------------------------------------------
  ! allocate wing storage for each wing
  !-------------------------------------------
    !TODO Add reading from backup file procedure

    do i = 1, nWings
    !---------------------------------------------
    ! define adjustable parameters for each wing
    ! this is position and motion protocoll
    !--------------------------------------------
    !rotation angles only used to determine the starting position of the wings
    wings(i)%Anglewing_x = 0.d0
    wings(i)%Anglewing_y = 0.d0
    wings(i)%Anglewing_z = -pi/4

    !--------------------------------------
    !-- initialize wing
    !--------------------------------------
    ! fetch leading edge position
    !call mouvement(0.d0, alpha, alpha_t, alpha_tt, LeadingEdge, wings(i) )
    ! initialize as zero
    wings(i)%x = 0.d0
    wings(i)%y = 0.d0
    wings(i)%z = 0.d0
    wings(i)%vx = 0.d0
    wings(i)%vy = 0.d0
    wings(i)%vz = 0.d0
    wings(i)%u_old = 0.d0
    wings(i)%u_oldold = 0.d0
    wings(i)%tri_elements = 0
    wings(i)%tri_element_areas = 0.d0
    wings(i)%tri_element_normals = 0.d0
    wings(i)%Veins_bending = 0.d0
    wings(i)%Veins_extension = 0.d0
    wings(i)%Veins_bending_BC = 0.d0
    wings(i)%Veins_extension_BC = 0.d0
    wings(i)%Membranes_extension = 0.d0
    wings(i)%Membrane_edge = 0.d0
    wings(i)%m=0.d0
    wings(i)%at_inertia=0.d0
    wings(i)%StartupStep = .true.
    wings(i)%dt_old = 0.d0
    wings(i)%press_upside = 0.d0
    wings(i)%press_downside = 0.d0

    ! Reading mesh data from ASCII files
    call read_wing_mesh_data(wings(i), i)


    !-----------------------------------------------------------------------------
    ! read in parameters form ini file
    !-----------------------------------------------------------------------------
    ! read in the complete ini file, from which we initialize the flexible wings
    call read_ini_file_mpi(PARAMS, fname, verbose=.true.)

    call read_param_mpi(PARAMS,"Geometry","x0",wings(i)%x0, 0.d0)
    call read_param_mpi(PARAMS,"Geometry","y0",wings(i)%y0, 0.d0)
    call read_param_mpi(PARAMS,"Geometry","z0",wings(i)%z0, 0.d0)
    !call read_param_mpi(PARAMS,"Flexible_wing","v0",wings(i)%v0, (/0.d0, 0.d0, 0.d0/))
    call read_param_mpi(PARAMS,"Flexible_wing","t_wing",wings(i)%t_wing, 0.01d0)
    call read_param_mpi(PARAMS,"Flexible_wing","wing_smoothing",wings(i)%wing_smoothing, 3*dz)

    call read_param_mpi(PARAMS,"Flexible_wing","EIy",wings(i)%EIy)
    call read_param_mpi(PARAMS,"Flexible_wing","EIz",wings(i)%EIz)
    call read_param_mpi(PARAMS,"Flexible_wing","EIy_with_BC",wings(i)%EIy_BC)
    call read_param_mpi(PARAMS,"Flexible_wing","EIz_with_BC",wings(i)%EIz_BC)

    call read_param_mpi(PARAMS,"Flexible_wing","ke_veins",wings(i)%ke0_v)
    call read_param_mpi(PARAMS,"Flexible_wing","ke_veins_with_BC",wings(i)%ke0_vBC)
    call read_param_mpi(PARAMS,"Flexible_wing","ke_membranes",wings(i)%ke0_m)

    call read_param_mpi(PARAMS,"Flexible_wing","density_veins",wings(i)%rho_v)
    call read_param_mpi(PARAMS,"Flexible_wing","density_veins_with_BC",wings(i)%rho_vBC)
    call read_param_mpi(PARAMS,"Flexible_wing","density_membranes",wings(i)%rho_m)

    call read_param_mpi(PARAMS,"Flexible_wing","damping",wings(i)%c0, 0.d0)

    call read_param_mpi(PARAMS,"Flexible_wing","Rotation_angle_x",wings(i)%Anglewing_x, 0.d0)
    call read_param_mpi(PARAMS,"Flexible_wing","Rotation_angle_y",wings(i)%Anglewing_y, 0.d0)
    call read_param_mpi(PARAMS,"Flexible_wing","Rotation_angle_z",wings(i)%Anglewing_z, 0.d0)

    call read_param_mpi(PARAMS,"Flexible_wing","Motion",wings(i)%Motion,"stationary")

    call read_param_mpi(PARAMS,"Flexible_wing","Gravity",grav, (/0.d0, 0.d0, -9.8d0/))
    call read_param_mpi(PARAMS,"Flexible_wing","use_flexible_wing_model",use_flexible_wing_model,"no")
    call read_param_mpi(PARAMS,"Flexible_wing","TimeMethodFlexibleSolid",TimeMethodFlexibleSolid,"BDF2")

    call read_param_mpi(PARAMS,"Flexible_wing","T_release",T_release,0.0d0)
    call read_param_mpi(PARAMS,"Flexible_wing","tau",tau,0.0d0)
    ! clean ini file
    call clean_ini_file_mpi(PARAMS)


    call rotate_wing(wings(i))

    !--------------------------------------------------------------------------
    ! Move the wing to the desired position X0
    !--------------------------------------------------------------------------
    !
    !  <--2*delta--><-delta->
    !  O-----O------X-------X---.....
    !               |................
    !               |.................
    !               |................
    !               x-----x----......
    !

    delta(1) = abs(wings(i)%x(nint(wings(i)%veins_bending_BC(1,3,1))) - &
                   wings(i)%x(nint(wings(i)%veins_bending_BC(1,2,1))))
    delta(2) = abs(wings(i)%y(nint(wings(i)%veins_bending_BC(1,3,1))) - &
                   wings(i)%y(nint(wings(i)%veins_bending_BC(1,2,1))))
    delta(3) = abs(wings(i)%z(nint(wings(i)%veins_bending_BC(1,3,1))) - &
                   wings(i)%z(nint(wings(i)%veins_bending_BC(1,2,1))))

    wings(i)%x = wings(i)%x + wings(i)%x0 + 2*delta(1)
    wings(i)%y = wings(i)%y + wings(i)%y0 + 2*delta(2)
    wings(i)%z = wings(i)%z + wings(i)%z0 + 2*delta(3)

    call determine_boundary_points_from_origin(wings(i))

    !--------------------------------------------------------------------------
    ! Determine initial geometrical properties of the wings: initial lengths,
    !  angles of springs and orientation of the wings
    !--------------------------------------------------------------------------
    allocate(normal(1:wings(i)%ntri,1:3))
    do itri=1,wings(i)%ntri
        ! Calculate the normal vector of one triangle
        normal(itri,1:3) = cross((/wings(i)%x(wings(i)%tri_elements(itri,2)) - &
                                   wings(i)%x(wings(i)%tri_elements(itri,3)),  &
                                   wings(i)%y(wings(i)%tri_elements(itri,2)) - &
                                   wings(i)%y(wings(i)%tri_elements(itri,3)),  &
                                   wings(i)%z(wings(i)%tri_elements(itri,2)) - &
                                   wings(i)%z(wings(i)%tri_elements(itri,3))/),&
                                 (/wings(i)%x(wings(i)%tri_elements(itri,3)) - &
                                   wings(i)%x(wings(i)%tri_elements(itri,4)),  &
                                   wings(i)%y(wings(i)%tri_elements(itri,3)) - &
                                   wings(i)%y(wings(i)%tri_elements(itri,4)),  &
                                   wings(i)%z(wings(i)%tri_elements(itri,3)) - &
                                   wings(i)%z(wings(i)%tri_elements(itri,4))/))

        ! dimentionalized to get a unit vector
        wings(i)%tri_element_normals(itri,1) = normal(itri,1)/norm2(normal(itri,1:3))
        wings(i)%tri_element_normals(itri,2) = normal(itri,2)/norm2(normal(itri,1:3))
        wings(i)%tri_element_normals(itri,3) = normal(itri,3)/norm2(normal(itri,1:3))

        !Calculate area of triangle elements
        wings(i)%tri_element_areas(itri) = 0.5*norm2(normal(itri,1:3))

        ! Check the orientation of the normal vectors comparing with Oz axis. This is
        ! done only at the first time step of the simulation.
        if (dot_product(wings(i)%tri_element_normals(itri,1:3),(/0.0d0,0.0d0,1.0d0/))<-1.0d-10) then
            wings(i)%tri_element_normals(itri,4) = -1
        elseif (dot_product(wings(i)%tri_element_normals(itri,1:3),(/0.0d0,0.0d0,1.0d0/))>1.0d-10) then
            wings(i)%tri_element_normals(itri,4) =  1
        else
            call abort(1412, "Wing normal vector is perpendicular with the Oz axis. &
                              The wing should be placed on the Oxy plane for the best performance of the solver.")
        endif
    enddo
    deallocate(normal)

    ! Update position and phase vector
    wings(i)%u_old(1:wings(i)%np)                 = wings(i)%x(1:wings(i)%np)
    wings(i)%u_old(wings(i)%np+1:2*wings(i)%np)   = wings(i)%y(1:wings(i)%np)
    wings(i)%u_old(2*wings(i)%np+1:3*wings(i)%np) = wings(i)%z(1:wings(i)%np)


    do j=1,nMembranes
        call length_calculation_wrapper(wings(i)%u_old(1:wings(i)%np), &
                                wings(i)%u_old(wings(i)%np+1:2*wings(i)%np), &
                                wings(i)%u_old(2*wings(i)%np+1:3*wings(i)%np),    &
                                wings(i)%membranes_extension(:,:,j))

        wings(i)%membranes_extension(:,4,j) = wings(i)%membranes_extension(:,5,j)

    enddo

    do j=1,nMembrane_edges
    call length_calculation_wrapper(wings(i)%u_old(1:wings(i)%np), &
                            wings(i)%u_old(wings(i)%np+1:2*wings(i)%np), &
                            wings(i)%u_old(2*wings(i)%np+1:3*wings(i)%np), &
                            wings(i)%membrane_edge(:,:,j))

            wings(i)%membrane_edge(:,4,j) = wings(i)%membrane_edge(:,5,j)
    enddo

    do j=1,nVeins

        call length_calculation_wrapper(wings(i)%u_old(1:wings(i)%np), &
                                wings(i)%u_old(wings(i)%np+1:2*wings(i)%np), &
                                wings(i)%u_old(2*wings(i)%np+1:3*wings(i)%np), &
                                wings(i)%veins_extension(:,:,j))


        call angle_calculation_wrapper(wings(i)%u_old(1:wings(i)%np), &
                               wings(i)%u_old(wings(i)%np+1:2*wings(i)%np), &
                               wings(i)%u_old(2*wings(i)%np+1:3*wings(i)%np), &
                               wings(i)%veins_bending(:,:,j))

        wings(i)%veins_extension(:,4,j) = wings(i)%veins_extension(:,5,j)
        wings(i)%veins_bending(:,5,j) = wings(i)%veins_bending(:,7,j)
        wings(i)%veins_bending(:,6,j) = wings(i)%veins_bending(:,8,j)

    enddo

    do j=1,nVeins_BC
        call length_calculation_wrapper(wings(i)%u_old(1:wings(i)%np), &
                                wings(i)%u_old(wings(i)%np+1:2*wings(i)%np), &
                                wings(i)%u_old(2*wings(i)%np+1:3*wings(i)%np),   &
                                wings(i)%veins_extension_BC(1:,:,j))
        call angle_calculation_wrapper(wings(i)%u_old(1:wings(i)%np), &
                               wings(i)%u_old(wings(i)%np+1:2*wings(i)%np), &
                               wings(i)%u_old(2*wings(i)%np+1:3*wings(i)%np), &
                               wings(i)%veins_bending_BC(1:,:,j))

        wings(i)%veins_extension_BC(1:,4,j) = wings(i)%veins_extension_BC(1:,5,j)
        wings(i)%veins_bending_BC(1:,5,j) = wings(i)%veins_bending_BC(1:,7,j)
        wings(i)%veins_bending_BC(1:,6,j) = wings(i)%veins_bending_BC(1:,8,j)
    end do


    !--------------------------------------------------------------------------
    ! Set up material properties
    !--------------------------------------------------------------------------

    do j=1,nMembranes
    wings(i)%ke_m(:,j) = wings(i)%ke0_m(j)
      do ind=1,nint(maxval(wings(i)%membranes(:,1,j)))
          wings(i)%m(nint(wings(i)%membranes(ind,2,j))) = wings(i)%rho_m(j)
      enddo
    enddo

    wings(i)%ke_me(:) = wings(i)%ke0_m(1)

    do j=1,nVeins
      call convert_flexural_rigidity_into_spring_stiffness(wings(i)%EIy(j), wings(i)%EIz(j),  &
                                                          wings(i)%kby0(j), wings(i)%kbz0(j), &
                                                          wings(i)%veins_extension(:,:,j))

      wings(i)%kby(:,j) = wings(i)%kby0(j)
      wings(i)%kbz(:,j) = wings(i)%kbz0(j)
      wings(i)%ke_v(:,j) = wings(i)%ke0_v(j)

      do ind=1,nint(maxval(wings(i)%veins(:,1,j)))
          wings(i)%m(nint(wings(i)%veins(ind,2,j))) = wings(i)%rho_v(j)
      enddo
    enddo

    do j=1,nVeins_BC
      call convert_flexural_rigidity_into_spring_stiffness(wings(i)%EIy_BC(j), wings(i)%EIz_BC(j),  &
                                                          wings(i)%kby0_BC(j), wings(i)%kbz0_BC(j), &
                                                          wings(i)%veins_extension_BC(1:,:,j))

      wings(i)%kby_BC(:,j) = wings(i)%kby0_BC(j)
      wings(i)%kbz_BC(:,j) = wings(i)%kbz0_BC(j)
      wings(i)%ke_vBC(:,j) = wings(i)%ke0_vBC(j)
      do ind=1,nint(maxval(wings(i)%veins_BC(:,1,j)))
          wings(i)%m(nint(wings(i)%veins_BC(ind,2,j))) = wings(i)%rho_vBC(j)
      enddo
    enddo



    if (mpirank ==0) then
      write(*,'(80("-"))')
      write(*,'("Setting up material properties for the wing number ",i2.2," with")') i
      write(frmt,'("(",i3.3,"(es12.4,1x))")') wings(i)%np
      write(*,*) "Mass points:"
      write(*,frmt) wings(i)%m(1:wings(i)%np)
      do j=1,nVeins_BC
        write(frmt,'("(",i3.3,"(es12.4,1x))")') nint(maxval(wings(i)%veins_bending_BC(:,1,j)))+2
        write(*,'("bending stiffness of y-direction bending springs of the vein with BC number ",i2.2,":")',advance='yes') j
        write(*,frmt) wings(i)%kby_BC(-1:nint(maxval(wings(i)%veins_bending_BC(:,1,j))),j)
        write(*,'("bending stiffness of z-direction bending springs of the vein with BC number ",i2.2,":")') j
        write(*,frmt) wings(i)%kbz_BC(-1:nint(maxval(wings(i)%veins_bending_BC(:,1,j))),j)
        write(frmt,'("(",i3.3,"(es12.4,1x))")') nint(maxval(wings(i)%veins_extension_BC(:,1,j)))+1
        write(*,'("extension stiffness of extension springs of the vein with BC number ",i2.2,":")') j
        write(*,frmt) wings(i)%ke_vBC(0:nint(maxval(wings(i)%veins_extension_BC(:,1,j))),j)
      enddo
      do j=1,nVeins
        write(frmt,'("(",i3.3,"(es12.4,1x))")') nint(maxval(wings(i)%veins_bending(:,1,j)))
        write(*,'("bending stiffness of y-direction bending springs of the vein number ",i2.2,":")',advance='yes') j
        write(*,frmt) wings(i)%kby(1:nint(maxval(wings(i)%veins_bending(:,1,j))),j)
        write(*,'("bending stiffness of z-direction bending springs of the vein number ",i2.2,":")') j
        write(*,frmt) wings(i)%kbz(1:nint(maxval(wings(i)%veins_bending(:,1,j))),j)
        write(frmt,'("(",i3.3,"(es12.4,1x))")') nint(maxval(wings(i)%veins_extension(:,1,j)))
        write(*,'("extension stiffness of extension springs of the vein number ",i2.2,":")') j
        write(*,frmt) wings(i)%ke_v(1:nint(maxval(wings(i)%veins_extension(:,1,j))),j)
      enddo
      do j=1,nMembranes
        write(frmt,'("(",i3.3,"(es12.4,1x))")') nint(maxval(wings(i)%membranes_extension(:,1,j)))
        write(*,'("extension stiffness of extension springs of the membrane number ",i2.2,":")',advance='yes') j
        write(*,frmt) wings(i)%ke_m(1:nint(maxval(wings(i)%membranes_extension(:,1,j))),j)
      enddo

    endif



    !if (TimeMethodSolid=="prescribed") then
    !  if(mpirank==0) write(*,*) "prescribed deformation: initializing..."
    !  call prescribed_wing ( 0.d0, 0.d0, wings(i) )
    !endif

  enddo

  !-------------------------------------------
  ! If we resume a backup, read from file (all ranks do that)
  !-------------------------------------------
  !if ( index(inicond,'backup::') /= 0 ) then
  !  fname = inicond(index(inicond,'::')+2:index(inicond,'.'))//'fsi_bckp'
  !  call read_solid_backup( wings, trim(adjustl(fname)) )
  !endif

  if (root) then
    write(*,'(80("<"))')
    write(*,*) "Flexible wings initialization is complete."
    write(*,'(80("<"))')
  endif

end subroutine init_wings

subroutine read_wing_mesh_data(wings, i)

  use vars
  implicit none
  integer, intent(in) :: i !ordinal number of the current wing
  type(flexible_wing), intent (inout) :: wings !for the ith wing
  character(len=strlen) :: data_file
  character(len=1)  :: wingstr
  integer :: j
  real(kind=pr), allocatable :: tmp2D(:,:)
  real(kind=pr), allocatable :: tmp1D(:,:)

    !-- for naming files..
    write (wingstr,'(i1)') i

    ! Read initial coordinates x,y,z of all points in 2nd,3rd,4th columms
    ! respectively in the points_coor.t data file
        data_file = 'points_coor'//wingstr//'.dat'
        call  read_mesh_data_2D_array(data_file, tmp2D)

        ! Saving number of points
        wings%np = nint(maxval(tmp2D(:,1)))

        do j=1, nint(maxval(tmp2D(:,1)))
          wings%x(j) = tmp2D(j,2)!*2*pi/xl*20
          wings%y(j) = tmp2D(j,3)!*2*pi/yl*20
          wings%z(j) = tmp2D(j,4)!*2*pi/zl
        end do

        deallocate(tmp2D)
    ! Read indices of three vertices (correnponding to 3rd, 4th and 5tn columms)
    ! of all triangle elements of the mesh
        data_file = 'mesh_triangle_elements'//wingstr//'.dat'
        call  read_mesh_data_2D_array(data_file, tmp2D)

        do j=1, size(tmp2D,DIM=1)
          wings%tri_elements(j,1) = j
          wings%tri_elements(j,2) = int(tmp2D(j,3))
          wings%tri_elements(j,3) = int(tmp2D(j,4))
          wings%tri_elements(j,4) = int(tmp2D(j,5))
        end do

        deallocate(tmp2D)
        ! Saving number of triangle elements
        wings%ntri = maxval(wings%tri_elements(:,1))

    ! Read identification numbers of all points belonging to veins
        data_file = 'veins'//wingstr//'.dat'
        call  read_mesh_data_2D_array(data_file, tmp2D)

        wings%veins(1:int((size(tmp2D,DIM=1))*(1.0/nVeins)),1:2,1:nVeins) = &
        reshape(tmp2D,(/int((size(tmp2D,DIM=1))*(1.0/nVeins)),2,nVeins/))

        deallocate(tmp2D)

    ! Read bending springs information of veins without boundary conditions
        data_file = 'veins_bending'//wingstr//'.dat'
        call  read_mesh_data_2D_array(data_file, tmp2D)

        wings%veins_bending(1:int((size(tmp2D,DIM=1))*(1.0/nVeins)),1:8,1:nVeins) = &
        reshape(tmp2D,(/int((size(tmp2D,DIM=1))*(1.0/nVeins)),8,nVeins/))

        deallocate(tmp2D)

     ! Read identification numbers of all points belonging to veins with BCs
         data_file = 'veins_BC'//wingstr//'.dat'
         call  read_mesh_data_2D_array(data_file, tmp2D)

         wings%veins_BC(1:int((size(tmp2D,DIM=1))*(1.0/nVeins_BC)),1:2,1:nVeins_BC) = &
         reshape(tmp2D,(/int((size(tmp2D,DIM=1))*(1.0/nVeins_BC)),2,nVeins_BC/))

         deallocate(tmp2D)

     ! Read bending springs information of veins with boundary conditions
        data_file = 'veins_bending_BC'//wingstr//'.dat'
        call  read_mesh_data_2D_array(data_file, tmp2D)

        wings%veins_bending_BC(1:int((size(tmp2D,DIM=1))*(1.0/nVeins_BC)),1:8,1:nVeins_BC) = &
        reshape(tmp2D,(/int((size(tmp2D,DIM=1))*(1.0/nVeins_BC)),8,nVeins_BC/))

        deallocate(tmp2D)

     ! Read extension springs information of veins without boundary conditions
        data_file = 'veins_extension'//wingstr//'.dat'
        call  read_mesh_data_2D_array(data_file, tmp2D)

        wings%veins_extension(1:int((size(tmp2D,DIM=1))*(1.0/nVeins)),1:5,1:nVeins) = &
        reshape(tmp2D,(/int((size(tmp2D,DIM=1))*(1.0/nVeins)),5,nVeins/))

        deallocate(tmp2D)

     ! Read extension springs information of veins with boundary conditions
        data_file = 'veins_extension_BC'//wingstr//'.dat'
        call  read_mesh_data_2D_array(data_file, tmp2D)

        wings%veins_extension_BC(1:int((size(tmp2D,DIM=1))*(1.0/nVeins_BC)),1:5,1:nVeins_BC) = &
        reshape(tmp2D,(/int((size(tmp2D,DIM=1))*(1.0/nVeins_BC)),5,nVeins_BC/))

        deallocate(tmp2D)

      ! TODO change back to general case when we have nMembranes membranes with 2D array
      ! Read identification numbers of all points belonging to membranes
         data_file = 'membranes'//wingstr//'.dat'
         call  read_mesh_data_1D_array(data_file, tmp1D)

         do j=1,int((size(tmp1D)))
         wings%membranes(j,2,1) = tmp1D(j,1)
         wings%membranes(j,1,1) = j
        enddo

         deallocate(tmp1D)

      ! Read extension springs information of membranes
         data_file = 'membranes_extension'//wingstr//'.dat'
         call  read_mesh_data_2D_array(data_file, tmp2D)

         wings%membranes_extension(1:int((size(tmp2D,DIM=1))*(1.0/nMembranes)),1:5,1:nMembranes) = &
         reshape(tmp2D,(/int((size(tmp2D,DIM=1))*(1.0/nMembranes)),5,nMembranes/))

         deallocate(tmp2D)

      ! Read extension springs information of the edge of the wing
        data_file = 'membrane_edge'//wingstr//'.dat'
        call  read_mesh_data_2D_array(data_file, tmp2D)

        wings%membrane_edge(1:int((size(tmp2D,DIM=1))*(1.0/nMembrane_edges)),1:5,1:nMembrane_edges) = &
        reshape(tmp2D,(/int((size(tmp2D,DIM=1))*(1.0/nMembrane_edges)),5,nMembrane_edges/))

        deallocate(tmp2D)


end subroutine read_wing_mesh_data

subroutine read_mesh_data_1D_array(data_file, data_1D_array)

character(len=strlen), intent(in) :: data_file
real(kind=pr),allocatable,intent(inout) :: data_1D_array(:,:)
integer :: num_lines, n_header=0

call count_lines_in_ascii_file_mpi(data_file, num_lines, n_header)
allocate(data_1D_array(1:num_lines,1) )
call read_array_from_ascii_file_mpi(data_file, data_1D_array, n_header)

end subroutine read_mesh_data_1D_array

subroutine read_mesh_data_2D_array(data_file, data_2D_array)

character(len=strlen), intent(in) :: data_file
real(kind=pr),allocatable,intent(inout) :: data_2D_array(:,:)
integer :: num_lines, num_cols, n_header=0

call count_lines_in_ascii_file_mpi(data_file, num_lines, n_header)
call count_cols_in_ascii_file_mpi(data_file, num_cols, n_header)
allocate(data_2D_array(1:num_lines, 1:num_cols) )
call read_array_from_ascii_file_mpi(data_file, data_2D_array, n_header)

end subroutine read_mesh_data_2D_array

subroutine determine_boundary_points_from_origin(wings)

  implicit none
  type(flexible_wing), intent (inout) :: wings
  integer :: i
  real(kind=pr), dimension(1:3) :: delta

  ! Calculate the second boundary point for the Leading edge vein from the first
  ! point which is read from param file since the first point of the LE vein is
  ! where we define the root of the wing (x0, y0, z0)
      wings%x_BC(-1,1) = wings%x0
      wings%y_BC(-1,1) = wings%y0
      wings%z_BC(-1,1) = wings%z0

      wings%x0_BC(-1,1) = wings%x_BC(-1,1)
      wings%y0_BC(-1,1) = wings%y_BC(-1,1)
      wings%z0_BC(-1,1) = wings%z_BC(-1,1)

      wings%x_BC(0,1) = (wings%x0 + wings%x(nint(wings%veins_bending_BC(1,2,1))))/2
      wings%y_BC(0,1) = (wings%y0 + wings%y(nint(wings%veins_bending_BC(1,2,1))))/2
      wings%z_BC(0,1) = (wings%z0 + wings%z(nint(wings%veins_bending_BC(1,2,1))))/2

      wings%x0_BC(0,1) = wings%x_BC(0,1)
      wings%y0_BC(0,1) = wings%y_BC(0,1)
      wings%z0_BC(0,1) = wings%z_BC(0,1)

      wings%veins_extension_BC(0,4,1) = sqrt(((wings%x0 - wings%x(nint(wings%veins_bending_BC(1,2,1))))/2)**2 + &
                                             ((wings%y0 - wings%y(nint(wings%veins_bending_BC(1,2,1))))/2)**2 + &
                                             ((wings%z0 - wings%z(nint(wings%veins_bending_BC(1,2,1))))/2)**2)

      ! Calculate initial angles
      call angle_calculation(wings%x_BC(0,1),wings%x(nint(wings%veins_bending_BC(1,2,1))), &
                             wings%x(nint(wings%veins_bending_BC(1,3,1))), wings%y_BC(0,1),&
                             wings%y(nint(wings%veins_bending_BC(1,2,1))),wings%y(nint(wings%veins_bending_BC(1,3,1))), &
                             wings%z_BC(0,1),wings%z(nint(wings%veins_bending_BC(1,2,1))), &
                             wings%z(nint(wings%veins_bending_BC(1,3,1))), &
                             wings%veins_bending_BC(0,5,1),wings%veins_bending_BC(0,6,1))


  ! Calculate boundary for other veins
      do i=2,nVeins_BC

        delta(1) = abs(wings%x(nint(wings%veins_bending_BC(1,3,i))) - &
                       wings%x(nint(wings%veins_bending_BC(1,2,i))))
        delta(2) = abs(wings%y(nint(wings%veins_bending_BC(1,3,i))) - &
                       wings%y(nint(wings%veins_bending_BC(1,2,i))))
        delta(3) = abs(wings%z(nint(wings%veins_bending_BC(1,3,i))) - &
                       wings%z(nint(wings%veins_bending_BC(1,2,i))))

        wings%x_BC(-1,i) = wings%x(nint(wings%veins_bending_BC(1,2,i))) - 2*delta(1)
        wings%y_BC(-1,i) = wings%y(nint(wings%veins_bending_BC(1,2,i))) - 2*delta(2)
        wings%z_BC(-1,i) = wings%z(nint(wings%veins_bending_BC(1,2,i))) - 2*delta(3)

        wings%x0_BC(-1,i) = wings%x_BC(-1,i)
        wings%y0_BC(-1,i) = wings%y_BC(-1,i)
        wings%z0_BC(-1,i) = wings%z_BC(-1,i)

        wings%x_BC(0,i) = (wings%x_BC(-1,i) + wings%x(nint(wings%veins_bending_BC(1,2,i))))/2
        wings%y_BC(0,i) = (wings%y_BC(-1,i) + wings%y(nint(wings%veins_bending_BC(1,2,i))))/2
        wings%z_BC(0,i) = (wings%z_BC(-1,i) + wings%z(nint(wings%veins_bending_BC(1,2,i))))/2

        wings%x0_BC(0,i) = wings%x_BC(0,i)
        wings%y0_BC(0,i) = wings%y_BC(0,i)
        wings%z0_BC(0,i) = wings%z_BC(0,i)

        ! Calculate initial lengths of springs connecting veins with the BC
        wings%veins_extension_BC(0,4,i) = sqrt((delta(1))**2 + (delta(2))**2 + (delta(3))**2)

        ! Calculate initial angles
        call angle_calculation(wings%x_BC(0,i),wings%x(nint(wings%veins_bending_BC(1,2,i))), &
                               wings%x(nint(wings%veins_bending_BC(1,3,i))), wings%y_BC(0,i),&
                               wings%y(nint(wings%veins_bending_BC(1,2,i))),wings%y(nint(wings%veins_bending_BC(1,3,i))), &
                               wings%z_BC(0,i),wings%z(nint(wings%veins_bending_BC(1,2,i))), &
                               wings%z(nint(wings%veins_bending_BC(1,3,i))), &
                               wings%veins_bending_BC(0,5,i),wings%veins_bending_BC(0,6,i))


      enddo

end subroutine
