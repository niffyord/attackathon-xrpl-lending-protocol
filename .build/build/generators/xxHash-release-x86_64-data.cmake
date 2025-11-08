########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

list(APPEND xxhash_COMPONENT_NAMES xxHash::xxhash)
list(REMOVE_DUPLICATES xxhash_COMPONENT_NAMES)
if(DEFINED xxhash_FIND_DEPENDENCY_NAMES)
  list(APPEND xxhash_FIND_DEPENDENCY_NAMES )
  list(REMOVE_DUPLICATES xxhash_FIND_DEPENDENCY_NAMES)
else()
  set(xxhash_FIND_DEPENDENCY_NAMES )
endif()

########### VARIABLES #######################################################################
#############################################################################################
set(xxhash_PACKAGE_FOLDER_RELEASE "/root/.conan2/p/xxhas4c80c8ebf4b2c/p")
set(xxhash_BUILD_MODULES_PATHS_RELEASE )


set(xxhash_INCLUDE_DIRS_RELEASE "${xxhash_PACKAGE_FOLDER_RELEASE}/include")
set(xxhash_RES_DIRS_RELEASE )
set(xxhash_DEFINITIONS_RELEASE )
set(xxhash_SHARED_LINK_FLAGS_RELEASE )
set(xxhash_EXE_LINK_FLAGS_RELEASE )
set(xxhash_OBJECTS_RELEASE )
set(xxhash_COMPILE_DEFINITIONS_RELEASE )
set(xxhash_COMPILE_OPTIONS_C_RELEASE )
set(xxhash_COMPILE_OPTIONS_CXX_RELEASE )
set(xxhash_LIB_DIRS_RELEASE "${xxhash_PACKAGE_FOLDER_RELEASE}/lib")
set(xxhash_BIN_DIRS_RELEASE )
set(xxhash_LIBRARY_TYPE_RELEASE STATIC)
set(xxhash_IS_HOST_WINDOWS_RELEASE 0)
set(xxhash_LIBS_RELEASE xxhash)
set(xxhash_SYSTEM_LIBS_RELEASE )
set(xxhash_FRAMEWORK_DIRS_RELEASE )
set(xxhash_FRAMEWORKS_RELEASE )
set(xxhash_BUILD_DIRS_RELEASE )
set(xxhash_NO_SONAME_MODE_RELEASE FALSE)


# COMPOUND VARIABLES
set(xxhash_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${xxhash_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${xxhash_COMPILE_OPTIONS_C_RELEASE}>")
set(xxhash_LINKER_FLAGS_RELEASE
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${xxhash_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${xxhash_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${xxhash_EXE_LINK_FLAGS_RELEASE}>")


set(xxhash_COMPONENTS_RELEASE xxHash::xxhash)
########### COMPONENT xxHash::xxhash VARIABLES ############################################

set(xxhash_xxHash_xxhash_INCLUDE_DIRS_RELEASE "${xxhash_PACKAGE_FOLDER_RELEASE}/include")
set(xxhash_xxHash_xxhash_LIB_DIRS_RELEASE "${xxhash_PACKAGE_FOLDER_RELEASE}/lib")
set(xxhash_xxHash_xxhash_BIN_DIRS_RELEASE )
set(xxhash_xxHash_xxhash_LIBRARY_TYPE_RELEASE STATIC)
set(xxhash_xxHash_xxhash_IS_HOST_WINDOWS_RELEASE 0)
set(xxhash_xxHash_xxhash_RES_DIRS_RELEASE )
set(xxhash_xxHash_xxhash_DEFINITIONS_RELEASE )
set(xxhash_xxHash_xxhash_OBJECTS_RELEASE )
set(xxhash_xxHash_xxhash_COMPILE_DEFINITIONS_RELEASE )
set(xxhash_xxHash_xxhash_COMPILE_OPTIONS_C_RELEASE "")
set(xxhash_xxHash_xxhash_COMPILE_OPTIONS_CXX_RELEASE "")
set(xxhash_xxHash_xxhash_LIBS_RELEASE xxhash)
set(xxhash_xxHash_xxhash_SYSTEM_LIBS_RELEASE )
set(xxhash_xxHash_xxhash_FRAMEWORK_DIRS_RELEASE )
set(xxhash_xxHash_xxhash_FRAMEWORKS_RELEASE )
set(xxhash_xxHash_xxhash_DEPENDENCIES_RELEASE )
set(xxhash_xxHash_xxhash_SHARED_LINK_FLAGS_RELEASE )
set(xxhash_xxHash_xxhash_EXE_LINK_FLAGS_RELEASE )
set(xxhash_xxHash_xxhash_NO_SONAME_MODE_RELEASE FALSE)

# COMPOUND VARIABLES
set(xxhash_xxHash_xxhash_LINKER_FLAGS_RELEASE
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${xxhash_xxHash_xxhash_SHARED_LINK_FLAGS_RELEASE}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${xxhash_xxHash_xxhash_SHARED_LINK_FLAGS_RELEASE}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${xxhash_xxHash_xxhash_EXE_LINK_FLAGS_RELEASE}>
)
set(xxhash_xxHash_xxhash_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${xxhash_xxHash_xxhash_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${xxhash_xxHash_xxhash_COMPILE_OPTIONS_C_RELEASE}>")