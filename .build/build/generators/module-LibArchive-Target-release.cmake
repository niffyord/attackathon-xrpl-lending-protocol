# Avoid multiple calls to find_package to append duplicated properties to the targets
include_guard()########### VARIABLES #######################################################################
#############################################################################################
set(libarchive_FRAMEWORKS_FOUND_RELEASE "") # Will be filled later
conan_find_apple_frameworks(libarchive_FRAMEWORKS_FOUND_RELEASE "${libarchive_FRAMEWORKS_RELEASE}" "${libarchive_FRAMEWORK_DIRS_RELEASE}")

set(libarchive_LIBRARIES_TARGETS "") # Will be filled later


######## Create an interface target to contain all the dependencies (frameworks, system and conan deps)
if(NOT TARGET libarchive_DEPS_TARGET)
    add_library(libarchive_DEPS_TARGET INTERFACE IMPORTED)
endif()

set_property(TARGET libarchive_DEPS_TARGET
             APPEND PROPERTY INTERFACE_LINK_LIBRARIES
             $<$<CONFIG:Release>:${libarchive_FRAMEWORKS_FOUND_RELEASE}>
             $<$<CONFIG:Release>:${libarchive_SYSTEM_LIBS_RELEASE}>
             $<$<CONFIG:Release>:LZ4::lz4_static>)

####### Find the libraries declared in cpp_info.libs, create an IMPORTED target for each one and link the
####### libarchive_DEPS_TARGET to all of them
conan_package_library_targets("${libarchive_LIBS_RELEASE}"    # libraries
                              "${libarchive_LIB_DIRS_RELEASE}" # package_libdir
                              "${libarchive_BIN_DIRS_RELEASE}" # package_bindir
                              "${libarchive_LIBRARY_TYPE_RELEASE}"
                              "${libarchive_IS_HOST_WINDOWS_RELEASE}"
                              libarchive_DEPS_TARGET
                              libarchive_LIBRARIES_TARGETS  # out_libraries_targets
                              "_RELEASE"
                              "libarchive"    # package_name
                              "${libarchive_NO_SONAME_MODE_RELEASE}")  # soname

# FIXME: What is the result of this for multi-config? All configs adding themselves to path?
set(CMAKE_MODULE_PATH ${libarchive_BUILD_DIRS_RELEASE} ${CMAKE_MODULE_PATH})

########## GLOBAL TARGET PROPERTIES Release ########################################
    set_property(TARGET LibArchive::LibArchive
                 APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                 $<$<CONFIG:Release>:${libarchive_OBJECTS_RELEASE}>
                 $<$<CONFIG:Release>:${libarchive_LIBRARIES_TARGETS}>
                 )

    if("${libarchive_LIBS_RELEASE}" STREQUAL "")
        # If the package is not declaring any "cpp_info.libs" the package deps, system libs,
        # frameworks etc are not linked to the imported targets and we need to do it to the
        # global target
        set_property(TARGET LibArchive::LibArchive
                     APPEND PROPERTY INTERFACE_LINK_LIBRARIES
                     libarchive_DEPS_TARGET)
    endif()

    set_property(TARGET LibArchive::LibArchive
                 APPEND PROPERTY INTERFACE_LINK_OPTIONS
                 $<$<CONFIG:Release>:${libarchive_LINKER_FLAGS_RELEASE}>)
    set_property(TARGET LibArchive::LibArchive
                 APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                 $<$<CONFIG:Release>:${libarchive_INCLUDE_DIRS_RELEASE}>)
    # Necessary to find LINK shared libraries in Linux
    set_property(TARGET LibArchive::LibArchive
                 APPEND PROPERTY INTERFACE_LINK_DIRECTORIES
                 $<$<CONFIG:Release>:${libarchive_LIB_DIRS_RELEASE}>)
    set_property(TARGET LibArchive::LibArchive
                 APPEND PROPERTY INTERFACE_COMPILE_DEFINITIONS
                 $<$<CONFIG:Release>:${libarchive_COMPILE_DEFINITIONS_RELEASE}>)
    set_property(TARGET LibArchive::LibArchive
                 APPEND PROPERTY INTERFACE_COMPILE_OPTIONS
                 $<$<CONFIG:Release>:${libarchive_COMPILE_OPTIONS_RELEASE}>)

########## For the modules (FindXXX)
set(libarchive_LIBRARIES_RELEASE LibArchive::LibArchive)
