# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(xxhash_FRAMEWORKS_FOUND_RELEASE "") # Will be filled later
conan_find_apple_frameworks(xxhash_FRAMEWORKS_FOUND_RELEASE "${xxhash_FRAMEWORKS_RELEASE}" "${xxhash_FRAMEWORK_DIRS_RELEASE}")

set(xxhash_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET xxhash_DEPS_TARGET)
    add_library(xxhash_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET xxhash_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Release>:${xxhash_FRAMEWORKS_FOUND_RELEASE}>
             $<$<CONFIG:Release>:${xxhash_SYSTEM_LIBS_RELEASE}>
             $<$<CONFIG:Release>:>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### xxhash_DEPS_TARGET to all of them
conan_package_library_targets("${xxhash_LIBS_RELEASE}"    # libraries
                              "${xxhash_LIB_DIRS_RELEASE}" # package_libdir
                              "${xxhash_BIN_DIRS_RELEASE}" # package_bindir
                              "${xxhash_LIBRARY_TYPE_RELEASE}"
                              "${xxhash_IS_HOST_WINDOWS_RELEASE}"
                              xxhash_DEPS_TARGET
                              xxhash_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELEASE"
                              "xxhash"    # package_name
                              "${xxhash_NO_SONAME_MODE_RELEASE}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${xxhash_BUILD_DIRS_RELEASE} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES Release ########################################

    ########## COMPONENT xxHash::xxhash #############

        set(xxhash_xxHash_xxhash_FRAMEWORKS_FOUND_RELEASE "")
        conan_find_apple_frameworks(xxhash_xxHash_xxhash_FRAMEWORKS_FOUND_RELEASE "${xxhash_xxHash_xxhash_FRAMEWORKS_RELEASE}" "${xxhash_xxHash_xxhash_FRAMEWORK_DIRS_RELEASE}")

        set(xxhash_xxHash_xxhash_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET xxhash_xxHash_xxhash_DEPS_TARGET)
            add_library(xxhash_xxHash_xxhash_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET xxhash_xxHash_xxhash_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_FRAMEWORKS_FOUND_RELEASE}>
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_SYSTEM_LIBS_RELEASE}>
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_DEPENDENCIES_RELEASE}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'xxhash_xxHash_xxhash_DEPS_TARGET' to all of them
        conan_package_library_targets("${xxhash_xxHash_xxhash_LIBS_RELEASE}"
                              "${xxhash_xxHash_xxhash_LIB_DIRS_RELEASE}"
                              "${xxhash_xxHash_xxhash_BIN_DIRS_RELEASE}" # package_bindir
                              "${xxhash_xxHash_xxhash_LIBRARY_TYPE_RELEASE}"
                              "${xxhash_xxHash_xxhash_IS_HOST_WINDOWS_RELEASE}"
                              xxhash_xxHash_xxhash_DEPS_TARGET
                              xxhash_xxHash_xxhash_LIBRARIES_TARGETS
                              "_RELEASE"
                              "xxhash_xxHash_xxhash"
                              "${xxhash_xxHash_xxhash_NO_SONAME_MODE_RELEASE}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET xxHash::xxhash
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_OBJECTS_RELEASE}>
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_LIBRARIES_TARGETS}>
                     )

        if("${xxhash_xxHash_xxhash_LIBS_RELEASE}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET xxHash::xxhash
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         xxhash_xxHash_xxhash_DEPS_TARGET)
        endif()

        set_property(TARGET xxHash::xxhash APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_LINKER_FLAGS_RELEASE}>)
        set_property(TARGET xxHash::xxhash APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_INCLUDE_DIRS_RELEASE}>)
        set_property(TARGET xxHash::xxhash APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_LIB_DIRS_RELEASE}>)
        set_property(TARGET xxHash::xxhash APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_COMPILE_DEFINITIONS_RELEASE}>)
        set_property(TARGET xxHash::xxhash APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:Release>:${xxhash_xxHash_xxhash_COMPILE_OPTIONS_RELEASE}>)


    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET xxHash::xxhash APPEND PROPERTY INTERFACE_LINK_LIBRARIES xxHash::xxhash)

########## For the modules (FindXXX)
set(xxhash_LIBRARIES_RELEASE xxHash::xxhash)
