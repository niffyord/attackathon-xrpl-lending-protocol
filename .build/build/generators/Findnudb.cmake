########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(nudb_FIND_QUIETLY)
    set(nudb_MESSAGE_MODE VERBOSE)
else()
    set(nudb_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/module-nudbTargets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${nudb_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(nudb_VERSION_STRING "2.0.9")
set(nudb_INCLUDE_DIRS ${nudb_INCLUDE_DIRS_RELEASE} )
set(nudb_INCLUDE_DIR ${nudb_INCLUDE_DIRS_RELEASE} )
set(nudb_LIBRARIES ${nudb_LIBRARIES_RELEASE} )
set(nudb_DEFINITIONS ${nudb_DEFINITIONS_RELEASE} )


# Definition of extra CMake variables from cmake_extra_variables


# Only the last installed configuration BUILD_MODULES are included to avoid the collision
foreach(_BUILD_MODULE ${nudb_BUILD_MODULES_PATHS_RELEASE} )
    message(${nudb_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


include(FindPackageHandleStandardArgs)
set(nudb_FOUND 1)
set(nudb_VERSION "2.0.9")

find_package_handle_standard_args(nudb
                                  REQUIRED_VARS nudb_VERSION
                                  VERSION_VAR nudb_VERSION)
mark_as_advanced(nudb_FOUND nudb_VERSION)

set(nudb_FOUND 1)
set(nudb_VERSION "2.0.9")
mark_as_advanced(nudb_FOUND nudb_VERSION)

