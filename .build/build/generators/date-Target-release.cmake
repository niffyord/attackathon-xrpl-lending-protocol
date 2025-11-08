# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(date_FRAMEWORKS_FOUND_RELEASE "") # Will be filled later
conan_find_apple_frameworks(date_FRAMEWORKS_FOUND_RELEASE "${date_FRAMEWORKS_RELEASE}" "${date_FRAMEWORK_DIRS_RELEASE}")

set(date_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET date_DEPS_TARGET)
    add_library(date_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET date_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Release>:${date_FRAMEWORKS_FOUND_RELEASE}>
             $<$<CONFIG:Release>:${date_SYSTEM_LIBS_RELEASE}>
             $<$<CONFIG:Release>:>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### date_DEPS_TARGET to all of them
conan_package_library_targets("${date_LIBS_RELEASE}"    # libraries
                              "${date_LIB_DIRS_RELEASE}" # package_libdir
                              "${date_BIN_DIRS_RELEASE}" # package_bindir
                              "${date_LIBRARY_TYPE_RELEASE}"
                              "${date_IS_HOST_WINDOWS_RELEASE}"
                              date_DEPS_TARGET
                              date_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELEASE"
                              "date"    # package_name
                              "${date_NO_SONAME_MODE_RELEASE}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${date_BUILD_DIRS_RELEASE} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES Release ########################################
    set_property(TARGET date::date
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:Release>:${date_OBJECTS_RELEASE}>
                 $<$<CONFIG:Release>:${date_LIBRARIES_TARGETS}>
                 )

    if("${date_LIBS_RELEASE}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET date::date
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     date_DEPS_TARGET)
    endif()

    set_property(TARGET date::date
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:Release>:${date_LINKER_FLAGS_RELEASE}>)
    set_property(TARGET date::date
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:Release>:${date_INCLUDE_DIRS_RELEASE}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET date::date
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:Release>:${date_LIB_DIRS_RELEASE}>)
    set_property(TARGET date::date
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:Release>:${date_COMPILE_DEFINITIONS_RELEASE}>)
    set_property(TARGET date::date
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:Release>:${date_COMPILE_OPTIONS_RELEASE}>)

########## For the modules (FindXXX)
set(date_LIBRARIES_RELEASE date::date)
