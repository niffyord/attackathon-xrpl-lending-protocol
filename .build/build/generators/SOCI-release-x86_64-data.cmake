########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

list(APPEND soci_COMPONENT_NAMES SOCI::soci_core_static)
list(REMOVE_DUPLICATES soci_COMPONENT_NAMES)
if(DEFINED soci_FIND_DEPENDENCY_NAMES)
  list(APPEND soci_FIND_DEPENDENCY_NAMES )
  list(REMOVE_DUPLICATES soci_FIND_DEPENDENCY_NAMES)
else()
  set(soci_FIND_DEPENDENCY_NAMES )
endif()

########### VARIABLES #######################################################################
#############################################################################################
set(soci_PACKAGE_FOLDER_RELEASE "/root/.conan2/p/soci81b134b9666e4/p")
set(soci_BUILD_MODULES_PATHS_RELEASE )


set(soci_INCLUDE_DIRS_RELEASE "${soci_PACKAGE_FOLDER_RELEASE}/include")
set(soci_RES_DIRS_RELEASE )
set(soci_DEFINITIONS_RELEASE )
set(soci_SHARED_LINK_FLAGS_RELEASE )
set(soci_EXE_LINK_FLAGS_RELEASE )
set(soci_OBJECTS_RELEASE )
set(soci_COMPILE_DEFINITIONS_RELEASE )
set(soci_COMPILE_OPTIONS_C_RELEASE )
set(soci_COMPILE_OPTIONS_CXX_RELEASE )
set(soci_LIB_DIRS_RELEASE "${soci_PACKAGE_FOLDER_RELEASE}/lib")
set(soci_BIN_DIRS_RELEASE )
set(soci_LIBRARY_TYPE_RELEASE STATIC)
set(soci_IS_HOST_WINDOWS_RELEASE 0)
set(soci_LIBS_RELEASE soci_core)
set(soci_SYSTEM_LIBS_RELEASE )
set(soci_FRAMEWORK_DIRS_RELEASE )
set(soci_FRAMEWORKS_RELEASE )
set(soci_BUILD_DIRS_RELEASE )
set(soci_NO_SONAME_MODE_RELEASE FALSE)


# COMPOUND VARIABLES
set(soci_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${soci_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${soci_COMPILE_OPTIONS_C_RELEASE}>")
set(soci_LINKER_FLAGS_RELEASE
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${soci_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${soci_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${soci_EXE_LINK_FLAGS_RELEASE}>")


set(soci_COMPONENTS_RELEASE SOCI::soci_core_static)
########### COMPONENT SOCI::soci_core_static VARIABLES ############################################

set(soci_SOCI_soci_core_static_INCLUDE_DIRS_RELEASE "${soci_PACKAGE_FOLDER_RELEASE}/include")
set(soci_SOCI_soci_core_static_LIB_DIRS_RELEASE "${soci_PACKAGE_FOLDER_RELEASE}/lib")
set(soci_SOCI_soci_core_static_BIN_DIRS_RELEASE )
set(soci_SOCI_soci_core_static_LIBRARY_TYPE_RELEASE STATIC)
set(soci_SOCI_soci_core_static_IS_HOST_WINDOWS_RELEASE 0)
set(soci_SOCI_soci_core_static_RES_DIRS_RELEASE )
set(soci_SOCI_soci_core_static_DEFINITIONS_RELEASE )
set(soci_SOCI_soci_core_static_OBJECTS_RELEASE )
set(soci_SOCI_soci_core_static_COMPILE_DEFINITIONS_RELEASE )
set(soci_SOCI_soci_core_static_COMPILE_OPTIONS_C_RELEASE "")
set(soci_SOCI_soci_core_static_COMPILE_OPTIONS_CXX_RELEASE "")
set(soci_SOCI_soci_core_static_LIBS_RELEASE soci_core)
set(soci_SOCI_soci_core_static_SYSTEM_LIBS_RELEASE )
set(soci_SOCI_soci_core_static_FRAMEWORK_DIRS_RELEASE )
set(soci_SOCI_soci_core_static_FRAMEWORKS_RELEASE )
set(soci_SOCI_soci_core_static_DEPENDENCIES_RELEASE )
set(soci_SOCI_soci_core_static_SHARED_LINK_FLAGS_RELEASE )
set(soci_SOCI_soci_core_static_EXE_LINK_FLAGS_RELEASE )
set(soci_SOCI_soci_core_static_NO_SONAME_MODE_RELEASE FALSE)

# COMPOUND VARIABLES
set(soci_SOCI_soci_core_static_LINKER_FLAGS_RELEASE
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${soci_SOCI_soci_core_static_SHARED_LINK_FLAGS_RELEASE}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${soci_SOCI_soci_core_static_SHARED_LINK_FLAGS_RELEASE}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${soci_SOCI_soci_core_static_EXE_LINK_FLAGS_RELEASE}>
)
set(soci_SOCI_soci_core_static_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${soci_SOCI_soci_core_static_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${soci_SOCI_soci_core_static_COMPILE_OPTIONS_C_RELEASE}>")