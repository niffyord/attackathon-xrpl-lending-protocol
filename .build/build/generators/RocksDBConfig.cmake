########## MACROS ###########################################################################
#############################################################################################

# Requires CMake > 3.15
if(${CMAKE_VERSION} VERSION_LESS "3.15")
    message(FATAL_ERROR "The 'CMakeDeps' generator only works with CMake >= 3.15")
endif()

if(RocksDB_FIND_QUIETLY)
    set(RocksDB_MESSAGE_MODE VERBOSE)
else()
    set(RocksDB_MESSAGE_MODE STATUS)
endif()

include(${CMAKE_CURRENT_LIST_DIR}/cmakedeps_macros.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/RocksDBTargets.cmake)
include(CMakeFindDependencyMacro)

check_build_type_defined()

foreach(_DEPENDENCY ${rocksdb_FIND_DEPENDENCY_NAMES} )
    # Check that we have not already called a find_package with the transitive dependency
    if(NOT ${_DEPENDENCY}_FOUND)
        find_dependency(${_DEPENDENCY} REQUIRED ${${_DEPENDENCY}_FIND_MODE})
    endif()
endforeach()

set(RocksDB_VERSION_STRING "10.0.1")
set(RocksDB_INCLUDE_DIRS ${rocksdb_INCLUDE_DIRS_RELEASE} )
set(RocksDB_INCLUDE_DIR ${rocksdb_INCLUDE_DIRS_RELEASE} )
set(RocksDB_LIBRARIES ${rocksdb_LIBRARIES_RELEASE} )
set(RocksDB_DEFINITIONS ${rocksdb_DEFINITIONS_RELEASE} )


# Definition of extra CMake variables from cmake_extra_variables


# Only the last installed configuration BUILD_MODULES are included to avoid the collision
foreach(_BUILD_MODULE ${rocksdb_BUILD_MODULES_PATHS_RELEASE} )
    message(${RocksDB_MESSAGE_MODE} "Conan: Including build module from '${_BUILD_MODULE}'")
    include(${_BUILD_MODULE})
endforeach()


