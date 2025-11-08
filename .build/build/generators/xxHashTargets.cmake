# Load the debug and release variables
file(GLOB DATA_FILES "${CMAKE_CURRENT_LIST_DIR}/xxHash-*-data.cmake")

foreach(f ${DATA_FILES})
    include(${f})
endforeach()

# Create the targets for all the components
foreach(_COMPONENT ${xxhash_COMPONENT_NAMES} )
    if(NOT TARGET ${_COMPONENT})
        add_library(${_COMPONENT} INTERFACE IMPORTED)
        message(${xxHash_MESSAGE_MODE} "Conan: Component target declared '${_COMPONENT}'")
    endif()
endforeach()

if(NOT TARGET xxHash::xxhash)
    add_library(xxHash::xxhash INTERFACE IMPORTED)
    message(${xxHash_MESSAGE_MODE} "Conan: Target declared 'xxHash::xxhash'")
endif()
# Load the debug and release library finders
file(GLOB CONFIG_FILES "${CMAKE_CURRENT_LIST_DIR}/xxHash-Target-*.cmake")

foreach(f ${CONFIG_FILES})
    include(${f})
endforeach()