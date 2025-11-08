########### AGGREGATED COMPONENTS AND DEPENDENCIES FOR THE MULTI CONFIG #####################
#############################################################################################

list(APPEND rocksdb_COMPONENT_NAMES RocksDB::rocksdb)
list(REMOVE_DUPLICATES rocksdb_COMPONENT_NAMES)
if(DEFINED rocksdb_FIND_DEPENDENCY_NAMES)
  list(APPEND rocksdb_FIND_DEPENDENCY_NAMES )
  list(REMOVE_DUPLICATES rocksdb_FIND_DEPENDENCY_NAMES)
else()
  set(rocksdb_FIND_DEPENDENCY_NAMES )
endif()

########### VARIABLES #######################################################################
#############################################################################################
set(rocksdb_PACKAGE_FOLDER_RELEASE "/root/.conan2/p/rocksbf75c49d251b2/p")
set(rocksdb_BUILD_MODULES_PATHS_RELEASE )


set(rocksdb_INCLUDE_DIRS_RELEASE "${rocksdb_PACKAGE_FOLDER_RELEASE}/include")
set(rocksdb_RES_DIRS_RELEASE )
set(rocksdb_DEFINITIONS_RELEASE )
set(rocksdb_SHARED_LINK_FLAGS_RELEASE )
set(rocksdb_EXE_LINK_FLAGS_RELEASE )
set(rocksdb_OBJECTS_RELEASE )
set(rocksdb_COMPILE_DEFINITIONS_RELEASE )
set(rocksdb_COMPILE_OPTIONS_C_RELEASE )
set(rocksdb_COMPILE_OPTIONS_CXX_RELEASE )
set(rocksdb_LIB_DIRS_RELEASE "${rocksdb_PACKAGE_FOLDER_RELEASE}/lib")
set(rocksdb_BIN_DIRS_RELEASE )
set(rocksdb_LIBRARY_TYPE_RELEASE STATIC)
set(rocksdb_IS_HOST_WINDOWS_RELEASE 0)
set(rocksdb_LIBS_RELEASE rocksdb)
set(rocksdb_SYSTEM_LIBS_RELEASE pthread m)
set(rocksdb_FRAMEWORK_DIRS_RELEASE )
set(rocksdb_FRAMEWORKS_RELEASE )
set(rocksdb_BUILD_DIRS_RELEASE )
set(rocksdb_NO_SONAME_MODE_RELEASE FALSE)


# COMPOUND VARIABLES
set(rocksdb_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${rocksdb_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${rocksdb_COMPILE_OPTIONS_C_RELEASE}>")
set(rocksdb_LINKER_FLAGS_RELEASE
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${rocksdb_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${rocksdb_SHARED_LINK_FLAGS_RELEASE}>"
    "$<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${rocksdb_EXE_LINK_FLAGS_RELEASE}>")


set(rocksdb_COMPONENTS_RELEASE RocksDB::rocksdb)
########### COMPONENT RocksDB::rocksdb VARIABLES ############################################

set(rocksdb_RocksDB_rocksdb_INCLUDE_DIRS_RELEASE "${rocksdb_PACKAGE_FOLDER_RELEASE}/include")
set(rocksdb_RocksDB_rocksdb_LIB_DIRS_RELEASE "${rocksdb_PACKAGE_FOLDER_RELEASE}/lib")
set(rocksdb_RocksDB_rocksdb_BIN_DIRS_RELEASE )
set(rocksdb_RocksDB_rocksdb_LIBRARY_TYPE_RELEASE STATIC)
set(rocksdb_RocksDB_rocksdb_IS_HOST_WINDOWS_RELEASE 0)
set(rocksdb_RocksDB_rocksdb_RES_DIRS_RELEASE )
set(rocksdb_RocksDB_rocksdb_DEFINITIONS_RELEASE )
set(rocksdb_RocksDB_rocksdb_OBJECTS_RELEASE )
set(rocksdb_RocksDB_rocksdb_COMPILE_DEFINITIONS_RELEASE )
set(rocksdb_RocksDB_rocksdb_COMPILE_OPTIONS_C_RELEASE "")
set(rocksdb_RocksDB_rocksdb_COMPILE_OPTIONS_CXX_RELEASE "")
set(rocksdb_RocksDB_rocksdb_LIBS_RELEASE rocksdb)
set(rocksdb_RocksDB_rocksdb_SYSTEM_LIBS_RELEASE pthread m)
set(rocksdb_RocksDB_rocksdb_FRAMEWORK_DIRS_RELEASE )
set(rocksdb_RocksDB_rocksdb_FRAMEWORKS_RELEASE )
set(rocksdb_RocksDB_rocksdb_DEPENDENCIES_RELEASE )
set(rocksdb_RocksDB_rocksdb_SHARED_LINK_FLAGS_RELEASE )
set(rocksdb_RocksDB_rocksdb_EXE_LINK_FLAGS_RELEASE )
set(rocksdb_RocksDB_rocksdb_NO_SONAME_MODE_RELEASE FALSE)

# COMPOUND VARIABLES
set(rocksdb_RocksDB_rocksdb_LINKER_FLAGS_RELEASE
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,SHARED_LIBRARY>:${rocksdb_RocksDB_rocksdb_SHARED_LINK_FLAGS_RELEASE}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,MODULE_LIBRARY>:${rocksdb_RocksDB_rocksdb_SHARED_LINK_FLAGS_RELEASE}>
        $<$<STREQUAL:$<TARGET_PROPERTY:TYPE>,EXECUTABLE>:${rocksdb_RocksDB_rocksdb_EXE_LINK_FLAGS_RELEASE}>
)
set(rocksdb_RocksDB_rocksdb_COMPILE_OPTIONS_RELEASE
    "$<$<COMPILE_LANGUAGE:CXX>:${rocksdb_RocksDB_rocksdb_COMPILE_OPTIONS_CXX_RELEASE}>"
    "$<$<COMPILE_LANGUAGE:C>:${rocksdb_RocksDB_rocksdb_COMPILE_OPTIONS_C_RELEASE}>")