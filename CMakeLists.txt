# Vehicle Edge Platform - Top-level CMake
# Builds all components in dependency order

cmake_minimum_required(VERSION 3.16)
project(vehicle-edge-platform VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Options
option(VEP_BUILD_TESTS "Build tests for all components" ON)
option(VEP_BUILD_EXAMPLES "Build examples for all components" ON)

# Components directory
set(COMPONENTS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/components)

# ==============================================================================
# Component 1: libvss-types (no dependencies)
# ==============================================================================
if(EXISTS ${COMPONENTS_DIR}/libvss-types/CMakeLists.txt)
    message(STATUS "Adding libvss-types")
    set(VSS_TYPES_BUILD_TESTS ${VEP_BUILD_TESTS} CACHE BOOL "" FORCE)
    set(VSS_TYPES_BUILD_EXAMPLES ${VEP_BUILD_EXAMPLES} CACHE BOOL "" FORCE)
    add_subdirectory(${COMPONENTS_DIR}/libvss-types ${CMAKE_BINARY_DIR}/libvss-types)
else()
    message(FATAL_ERROR "libvss-types not found. Run ./setup.sh first.")
endif()

# ==============================================================================
# Component 2: libvssdag (depends on libvss-types)
# ==============================================================================
if(EXISTS ${COMPONENTS_DIR}/libvssdag/CMakeLists.txt)
    message(STATUS "Adding libvssdag")
    set(BUILD_TESTS ${VEP_BUILD_TESTS} CACHE BOOL "" FORCE)
    set(BUILD_EXAMPLES ${VEP_BUILD_EXAMPLES} CACHE BOOL "" FORCE)
    add_subdirectory(${COMPONENTS_DIR}/libvssdag ${CMAKE_BINARY_DIR}/libvssdag)
else()
    message(FATAL_ERROR "libvssdag not found. Run ./setup.sh first.")
endif()

# ==============================================================================
# Component 3: libkuksa-cpp (depends on libvss-types)
# ==============================================================================
if(EXISTS ${COMPONENTS_DIR}/libkuksa-cpp/CMakeLists.txt)
    message(STATUS "Adding libkuksa-cpp")
    set(BUILD_TESTS ${VEP_BUILD_TESTS} CACHE BOOL "" FORCE)
    set(BUILD_EXAMPLES ${VEP_BUILD_EXAMPLES} CACHE BOOL "" FORCE)
    add_subdirectory(${COMPONENTS_DIR}/libkuksa-cpp ${CMAKE_BINARY_DIR}/libkuksa-cpp)
else()
    message(WARNING "libkuksa-cpp not found, skipping (Kuksa bridge will not be built)")
endif()

# ==============================================================================
# Component 4: vep-dds (depends on libvss-types)
# ==============================================================================
if(EXISTS ${COMPONENTS_DIR}/vep-dds/CMakeLists.txt)
    message(STATUS "Adding vep-dds")
    set(VDR_LIGHT_BUILD_EXAMPLES ${VEP_BUILD_EXAMPLES} CACHE BOOL "" FORCE)
    add_subdirectory(${COMPONENTS_DIR}/vep-dds ${CMAKE_BINARY_DIR}/vep-dds)
else()
    message(FATAL_ERROR "vep-dds not found. Run ./setup.sh first.")
endif()

# ==============================================================================
# Component 5: vep-core (depends on all above)
# ==============================================================================
if(EXISTS ${COMPONENTS_DIR}/vep-core/CMakeLists.txt)
    message(STATUS "Adding vep-core")
    add_subdirectory(${COMPONENTS_DIR}/vep-core ${CMAKE_BINARY_DIR}/vep-core)
else()
    message(FATAL_ERROR "vep-core not found. Run ./setup.sh first.")
endif()

# ==============================================================================
# Summary
# ==============================================================================
message(STATUS "")
message(STATUS "=== Vehicle Edge Platform ===")
message(STATUS "Components:")
message(STATUS "  - libvss-types")
message(STATUS "  - libvssdag")
if(EXISTS ${COMPONENTS_DIR}/libkuksa-cpp/CMakeLists.txt)
message(STATUS "  - libkuksa-cpp")
endif()
message(STATUS "  - vep-dds")
message(STATUS "  - vep-core")
message(STATUS "")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "Tests: ${VEP_BUILD_TESTS}")
message(STATUS "Examples: ${VEP_BUILD_EXAMPLES}")
message(STATUS "")
