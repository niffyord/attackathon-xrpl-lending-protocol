# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(rocksdb_FRAMEWORKS_FOUND_RELEASE "") # Will be filled later
conan_find_apple_frameworks(rocksdb_FRAMEWORKS_FOUND_RELEASE "${rocksdb_FRAMEWORKS_RELEASE}" "${rocksdb_FRAMEWORK_DIRS_RELEASE}")

set(rocksdb_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET rocksdb_DEPS_TARGET)
    add_library(rocksdb_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET rocksdb_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Release>:${rocksdb_FRAMEWORKS_FOUND_RELEASE}>
             $<$<CONFIG:Release>:${rocksdb_SYSTEM_LIBS_RELEASE}>
             $<$<CONFIG:Release>:>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### rocksdb_DEPS_TARGET to all of them
conan_package_library_targets("${rocksdb_LIBS_RELEASE}"    # libraries
                              "${rocksdb_LIB_DIRS_RELEASE}" # package_libdir
                              "${rocksdb_BIN_DIRS_RELEASE}" # package_bindir
                              "${rocksdb_LIBRARY_TYPE_RELEASE}"
                              "${rocksdb_IS_HOST_WINDOWS_RELEASE}"
                              rocksdb_DEPS_TARGET
                              rocksdb_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELEASE"
                              "rocksdb"    # package_name
                              "${rocksdb_NO_SONAME_MODE_RELEASE}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${rocksdb_BUILD_DIRS_RELEASE} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES Release ########################################

    ########## COMPONENT RocksDB::rocksdb #############

        set(rocksdb_RocksDB_rocksdb_FRAMEWORKS_FOUND_RELEASE "")
        conan_find_apple_frameworks(rocksdb_RocksDB_rocksdb_FRAMEWORKS_FOUND_RELEASE "${rocksdb_RocksDB_rocksdb_FRAMEWORKS_RELEASE}" "${rocksdb_RocksDB_rocksdb_FRAMEWORK_DIRS_RELEASE}")

        set(rocksdb_RocksDB_rocksdb_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET rocksdb_RocksDB_rocksdb_DEPS_TARGET)
            add_library(rocksdb_RocksDB_rocksdb_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET rocksdb_RocksDB_rocksdb_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_FRAMEWORKS_FOUND_RELEASE}>
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_SYSTEM_LIBS_RELEASE}>
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_DEPENDENCIES_RELEASE}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'rocksdb_RocksDB_rocksdb_DEPS_TARGET' to all of them
        conan_package_library_targets("${rocksdb_RocksDB_rocksdb_LIBS_RELEASE}"
                              "${rocksdb_RocksDB_rocksdb_LIB_DIRS_RELEASE}"
                              "${rocksdb_RocksDB_rocksdb_BIN_DIRS_RELEASE}" # package_bindir
                              "${rocksdb_RocksDB_rocksdb_LIBRARY_TYPE_RELEASE}"
                              "${rocksdb_RocksDB_rocksdb_IS_HOST_WINDOWS_RELEASE}"
                              rocksdb_RocksDB_rocksdb_DEPS_TARGET
                              rocksdb_RocksDB_rocksdb_LIBRARIES_TARGETS
                              "_RELEASE"
                              "rocksdb_RocksDB_rocksdb"
                              "${rocksdb_RocksDB_rocksdb_NO_SONAME_MODE_RELEASE}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET RocksDB::rocksdb
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_OBJECTS_RELEASE}>
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_LIBRARIES_TARGETS}>
                     )

        if("${rocksdb_RocksDB_rocksdb_LIBS_RELEASE}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET RocksDB::rocksdb
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         rocksdb_RocksDB_rocksdb_DEPS_TARGET)
        endif()

        set_property(TARGET RocksDB::rocksdb APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_LINKER_FLAGS_RELEASE}>)
        set_property(TARGET RocksDB::rocksdb APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_INCLUDE_DIRS_RELEASE}>)
        set_property(TARGET RocksDB::rocksdb APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_LIB_DIRS_RELEASE}>)
        set_property(TARGET RocksDB::rocksdb APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_COMPILE_DEFINITIONS_RELEASE}>)
        set_property(TARGET RocksDB::rocksdb APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:Release>:${rocksdb_RocksDB_rocksdb_COMPILE_OPTIONS_RELEASE}>)


    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET RocksDB::rocksdb APPEND PROPERTY INTERFACE_LINK_LIBRARIES RocksDB::rocksdb)

########## For the modules (FindXXX)
set(rocksdb_LIBRARIES_RELEASE RocksDB::rocksdb)
