# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(soci_FRAMEWORKS_FOUND_RELEASE "") # Will be filled later
conan_find_apple_frameworks(soci_FRAMEWORKS_FOUND_RELEASE "${soci_FRAMEWORKS_RELEASE}" "${soci_FRAMEWORK_DIRS_RELEASE}")

set(soci_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET soci_DEPS_TARGET)
    add_library(soci_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET soci_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Release>:${soci_FRAMEWORKS_FOUND_RELEASE}>
             $<$<CONFIG:Release>:${soci_SYSTEM_LIBS_RELEASE}>
             $<$<CONFIG:Release>:>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### soci_DEPS_TARGET to all of them
conan_package_library_targets("${soci_LIBS_RELEASE}"    # libraries
                              "${soci_LIB_DIRS_RELEASE}" # package_libdir
                              "${soci_BIN_DIRS_RELEASE}" # package_bindir
                              "${soci_LIBRARY_TYPE_RELEASE}"
                              "${soci_IS_HOST_WINDOWS_RELEASE}"
                              soci_DEPS_TARGET
                              soci_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELEASE"
                              "soci"    # package_name
                              "${soci_NO_SONAME_MODE_RELEASE}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${soci_BUILD_DIRS_RELEASE} ${CMAKE_MODULE_PATH})

########## COMPONENTS TARGET PROPERTIES Release ########################################

    ########## COMPONENT SOCI::soci_core_static #############

        set(soci_SOCI_soci_core_static_FRAMEWORKS_FOUND_RELEASE "")
        conan_find_apple_frameworks(soci_SOCI_soci_core_static_FRAMEWORKS_FOUND_RELEASE "${soci_SOCI_soci_core_static_FRAMEWORKS_RELEASE}" "${soci_SOCI_soci_core_static_FRAMEWORK_DIRS_RELEASE}")

        set(soci_SOCI_soci_core_static_LIBRARIES_TARGETS "")

        ######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
        if(NOT TARGET soci_SOCI_soci_core_static_DEPS_TARGET)
            add_library(soci_SOCI_soci_core_static_DEPS_TARGET INTERFACE IMPORTED)
        endif()

        set_property(TARGET soci_SOCI_soci_core_static_DEPS_TARGET
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_FRAMEWORKS_FOUND_RELEASE}>
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_SYSTEM_LIBS_RELEASE}>
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_DEPENDENCIES_RELEASE}>
                     )

        ####### Find the libraries declared in cpp_info.component["xxx"].libs,
        ####### create an IMPORTED target for each one and link the 'soci_SOCI_soci_core_static_DEPS_TARGET' to all of them
        conan_package_library_targets("${soci_SOCI_soci_core_static_LIBS_RELEASE}"
                              "${soci_SOCI_soci_core_static_LIB_DIRS_RELEASE}"
                              "${soci_SOCI_soci_core_static_BIN_DIRS_RELEASE}" # package_bindir
                              "${soci_SOCI_soci_core_static_LIBRARY_TYPE_RELEASE}"
                              "${soci_SOCI_soci_core_static_IS_HOST_WINDOWS_RELEASE}"
                              soci_SOCI_soci_core_static_DEPS_TARGET
                              soci_SOCI_soci_core_static_LIBRARIES_TARGETS
                              "_RELEASE"
                              "soci_SOCI_soci_core_static"
                              "${soci_SOCI_soci_core_static_NO_SONAME_MODE_RELEASE}")


        ########## TARGET PROPERTIES #####################################
        set_property(TARGET SOCI::soci_core_static
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_OBJECTS_RELEASE}>
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_LIBRARIES_TARGETS}>
                     )

        if("${soci_SOCI_soci_core_static_LIBS_RELEASE}" STREQUAL "")
            # If the component is not declaring any "cpp_info.components['foo'].libs" the system, frameworks etc are not
            # linked to the imported targets and we need to do it to the global target
            set_property(TARGET SOCI::soci_core_static
                         APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                         soci_SOCI_soci_core_static_DEPS_TARGET)
        endif()

        set_property(TARGET SOCI::soci_core_static APPEND PROPERTY INTERFACE_LINK_OPTIONS
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_LINKER_FLAGS_RELEASE}>)
        set_property(TARGET SOCI::soci_core_static APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_INCLUDE_DIRS_RELEASE}>)
        set_property(TARGET SOCI::soci_core_static APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_LIB_DIRS_RELEASE}>)
        set_property(TARGET SOCI::soci_core_static APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_COMPILE_DEFINITIONS_RELEASE}>)
        set_property(TARGET SOCI::soci_core_static APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                     $<$<CONFIG:Release>:${soci_SOCI_soci_core_static_COMPILE_OPTIONS_RELEASE}>)


    ########## AGGREGATED GLOBAL TARGET WITH THE COMPONENTS #####################
    set_property(TARGET soci::soci APPEND PROPERTY INTERFACE_LINK_LIBRARIES SOCI::soci_core_static)

########## For the modules (FindXXX)
set(soci_LIBRARIES_RELEASE soci::soci)
