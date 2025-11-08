# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(nudb_FRAMEWORKS_FOUND_RELEASE "") # Will be filled later
conan_find_apple_frameworks(nudb_FRAMEWORKS_FOUND_RELEASE "${nudb_FRAMEWORKS_RELEASE}" "${nudb_FRAMEWORK_DIRS_RELEASE}")

set(nudb_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET nudb_DEPS_TARGET)
    add_library(nudb_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET nudb_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Release>:${nudb_FRAMEWORKS_FOUND_RELEASE}>
             $<$<CONFIG:Release>:${nudb_SYSTEM_LIBS_RELEASE}>
             $<$<CONFIG:Release>:Boost::thread;Boost::system>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### nudb_DEPS_TARGET to all of them
conan_package_library_targets("${nudb_LIBS_RELEASE}"    # libraries
                              "${nudb_LIB_DIRS_RELEASE}" # package_libdir
                              "${nudb_BIN_DIRS_RELEASE}" # package_bindir
                              "${nudb_LIBRARY_TYPE_RELEASE}"
                              "${nudb_IS_HOST_WINDOWS_RELEASE}"
                              nudb_DEPS_TARGET
                              nudb_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELEASE"
                              "nudb"    # package_name
                              "${nudb_NO_SONAME_MODE_RELEASE}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${nudb_BUILD_DIRS_RELEASE} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES Release ########################################

    ########## COMPONENT nudb #############

        set(nudb_nudb_FRAMEWORKS_FOUND_RELEASE "")
        conan_find_apple_frameworks(nudb_nudb_FRAMEWORKS_FOUND_RELEASE "${nudb_nudb_FRAMEWORKS_RELEASE}" "${nudb_nudb_FRAMEWORK_DIRS_RELEASE}")

        set(nudb_nudb_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET nudb_nudb_DEPS_TARGET)
            add_library(nudb_nudb_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET nudb_nudb_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${nudb_nudb_FRAMEWORKS_FOUND_RELEASE}>
                     $<$<CONFIG:Release>:${nudb_nudb_SYSTEM_LIBS_RELEASE}>
                     $<$<CONFIG:Release>:${nudb_nudb_DEPENDENCIES_RELEASE}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'nudb_nudb_DEPS_TARGET' to all of them
        conan_package_library_targets("${nudb_nudb_LIBS_RELEASE}"
                              "${nudb_nudb_LIB_DIRS_RELEASE}"
                              "${nudb_nudb_BIN_DIRS_RELEASE}" # package_bindir
                              "${nudb_nudb_LIBRARY_TYPE_RELEASE}"
                              "${nudb_nudb_IS_HOST_WINDOWS_RELEASE}"
                              nudb_nudb_DEPS_TARGET
                              nudb_nudb_LIBRARIES_TARGETS
                              "_RELEASE"
                              "nudb_nudb"
                              "${nudb_nudb_NO_SONAME_MODE_RELEASE}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET nudb
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${nudb_nudb_OBJECTS_RELEASE}>
                     $<$<CONFIG:Release>:${nudb_nudb_LIBRARIES_TARGETS}>
                     )

        if("${nudb_nudb_LIBS_RELEASE}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET nudb
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         nudb_nudb_DEPS_TARGET)
        endif()

        set_property(TARGET nudb APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:Release>:${nudb_nudb_LINKER_FLAGS_RELEASE}>)
        set_property(TARGET nudb APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:Release>:${nudb_nudb_INCLUDE_DIRS_RELEASE}>)
        set_property(TARGET nudb APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:Release>:${nudb_nudb_LIB_DIRS_RELEASE}>)
        set_property(TARGET nudb APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:Release>:${nudb_nudb_COMPILE_DEFINITIONS_RELEASE}>)
        set_property(TARGET nudb APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:Release>:${nudb_nudb_COMPILE_OPTIONS_RELEASE}>)


    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET NuDB APPEND PROPERTY INTERFACE_LINK_LIBRARIES nudb)

########## For the modules (FindXXX)
set(nudb_LIBRARIES_RELEASE NuDB)
