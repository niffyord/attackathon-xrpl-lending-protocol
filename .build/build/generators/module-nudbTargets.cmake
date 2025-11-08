# Load the debug and release variables
file(GLOB DATA_FILES "${CMAKE_CURRENT_LIST_DIR}/module-nudb-*-data.cmake")

foreach(f ${DATA_FILES})
    include(${f})
endforeach()

# Create the targets for all the components
foreach(_COMPONENT ${nudb_COMPONENT_NAMES} )
    if(NOT TARGET ${_COMPONENT})
        add_library(${_COMPONENT} INTERFACE IMPORTED)
        message(${nudb_MESSAGE_MODE} "Conan: Component target declared '${_COMPONENT}'")
    endif()
endforeach()

if(NOT TARGET NuDB)
    add_library(NuDB INTERFACE IMPORTED)
    message(${nudb_MESSAGE_MODE} "Conan: Target declared 'NuDB'")
endif()
if(NOT TARGET NuDB::nudb)
    add_library(NuDB::nudb INTERFACE IMPORTED)
    set_property(TARGET NuDB::nudb PROPERTY INTERFACE_LINK_LIBRARIES NuDB)
endif()
# Load the debug and release library finders
file(GLOB CONFIG_FILES "${CMAKE_CURRENT_LIST_DIR}/module-nudb-Target-*.cmake")

foreach(f ${CONFIG_FILES})
    include(${f})
endforeach()