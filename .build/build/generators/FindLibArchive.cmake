########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(LibArchive_FIND_QUIETLY)
    set(LibArchive_MESSAGE_MODE VERBOSE)
else()
    set(LibArchive_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/module-LibArchiveTargets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${libarchive_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(LibArchive_VERSION_STRING "3.8.1")
set(LibArchive_INCLUDE_DIRS ${libarchive_INCLUDE_DIRS_RELEASE} )
set(LibArchive_INCLUDE_DIR ${libarchive_INCLUDE_DIRS_RELEASE} )
set(LibArchive_LIBRARIES ${libarchive_LIBRARIES_RELEASE} )
set(LibArchive_DEFINITIONS ${libarchive_DEFINITIONS_RELEASE} )


# Definition of extra CMake variables from cmake_extra_variables


# Only the last installed configuration BUILD_MODULES are included to avoid the collision
foreach(_BUILD_MODULE ${libarchive_BUILD_MODULES_PATHS_RELEASE} )
    message(${LibArchive_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


include(FindPackageHandleStandardArgs)
set(LibArchive_FOUND 1)
set(LibArchive_VERSION "3.8.1")

find_package_handle_standard_args(LibArchive
                                  REQUIRED_VARS LibArchive_VERSION
                                  VERSION_VAR LibArchive_VERSION)
mark_as_advanced(LibArchive_FOUND LibArchive_VERSION)

set(LibArchive_FOUND 1)
set(LibArchive_VERSION "3.8.1")
mark_as_advanced(LibArchive_FOUND LibArchive_VERSION)

