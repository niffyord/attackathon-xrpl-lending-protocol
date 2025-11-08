# Load the debug and release variables
file(GLOB DATA_FILES "${CMAKE_CURRENT_LIST_DIR}/RocksDB-*-data.cmake")

foreach(f ${DATA_FILES})
    include(${f})
endforeach()

# Create the targets for all the components
foreach(_COMPONENT ${rocksdb_COMPONENT_NAMES} )
    if(NOT TARGET ${_COMPONENT})
        add_library(${_COMPONENT} INTERFACE IMPORTED)
        message(${RocksDB_MESSAGE_MODE} "Conan: Component target declared '${_COMPONENT}'")
    endif()
endforeach()

if(NOT TARGET RocksDB::rocksdb)
    add_library(RocksDB::rocksdb INTERFACE IMPORTED)
    message(${RocksDB_MESSAGE_MODE} "Conan: Target declared 'RocksDB::rocksdb'")
endif()
# Load the debug and release library finders
file(GLOB CONFIG_FILES "${CMAKE_CURRENT_LIST_DIR}/RocksDB-Target-*.cmake")

foreach(f ${CONFIG_FILES})
    include(${f})
endforeach()