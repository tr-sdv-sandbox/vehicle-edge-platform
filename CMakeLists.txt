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

# Enable testing at the top level so ctest can discover all component tests
if(VEP_BUILD_TESTS)
    enable_testing()
endif()

# Components directory
set(COMPONENTS_DIR ${CMAKE_CURRENT_SOURCE_DIR}/components)

# ==============================================================================
# Compile IDL from vep-schema (single source of truth)
# ==============================================================================
# This is done at top-level so all components can use the same IDL library

find_package(CycloneDDS REQUIRED)
find_program(IDLC_EXECUTABLE idlc REQUIRED)

set(IDL_OUTPUT_DIR ${CMAKE_BINARY_DIR}/generated_idl)
file(MAKE_DIRECTORY ${IDL_OUTPUT_DIR})

# Path to vep-schema IDL files
set(VEP_SCHEMA_IDL_DIR "${COMPONENTS_DIR}/vep-schema/generated/idl")

if(NOT EXISTS "${VEP_SCHEMA_IDL_DIR}/types.idl")
    message(FATAL_ERROR "vep-schema IDL not found at ${VEP_SCHEMA_IDL_DIR}. Run vep-schema/generate-all.sh first.")
endif()

# IDL files from vep-schema
set(TYPES_IDL ${VEP_SCHEMA_IDL_DIR}/types.idl)
set(VSS_SIGNAL_IDL ${VEP_SCHEMA_IDL_DIR}/vss-signal.idl)
set(AVTP_IDL ${VEP_SCHEMA_IDL_DIR}/avtp.idl)
set(OTEL_METRICS_IDL ${VEP_SCHEMA_IDL_DIR}/otel-metrics.idl)
set(OTEL_LOGS_IDL ${VEP_SCHEMA_IDL_DIR}/otel-logs.idl)
set(DIAGNOSTICS_IDL ${VEP_SCHEMA_IDL_DIR}/diagnostics.idl)
set(EVENTS_IDL ${VEP_SCHEMA_IDL_DIR}/events.idl)
set(OPAQUE_IDL ${VEP_SCHEMA_IDL_DIR}/opaque.idl)
set(SECURITY_IDL ${VEP_SCHEMA_IDL_DIR}/security.idl)
set(UDS_DTC_IDL ${VEP_SCHEMA_IDL_DIR}/uds-dtc.idl)

# Generated files
set(TYPES_IDL_SRC ${IDL_OUTPUT_DIR}/types.c)
set(TYPES_IDL_HDR ${IDL_OUTPUT_DIR}/types.h)
set(VSS_SIGNAL_IDL_SRC ${IDL_OUTPUT_DIR}/vss-signal.c)
set(VSS_SIGNAL_IDL_HDR ${IDL_OUTPUT_DIR}/vss-signal.h)
set(AVTP_IDL_SRC ${IDL_OUTPUT_DIR}/avtp.c)
set(AVTP_IDL_HDR ${IDL_OUTPUT_DIR}/avtp.h)
set(OTEL_METRICS_IDL_SRC ${IDL_OUTPUT_DIR}/otel-metrics.c)
set(OTEL_METRICS_IDL_HDR ${IDL_OUTPUT_DIR}/otel-metrics.h)
set(OTEL_LOGS_IDL_SRC ${IDL_OUTPUT_DIR}/otel-logs.c)
set(OTEL_LOGS_IDL_HDR ${IDL_OUTPUT_DIR}/otel-logs.h)
set(DIAGNOSTICS_IDL_SRC ${IDL_OUTPUT_DIR}/diagnostics.c)
set(DIAGNOSTICS_IDL_HDR ${IDL_OUTPUT_DIR}/diagnostics.h)
set(EVENTS_IDL_SRC ${IDL_OUTPUT_DIR}/events.c)
set(EVENTS_IDL_HDR ${IDL_OUTPUT_DIR}/events.h)
set(OPAQUE_IDL_SRC ${IDL_OUTPUT_DIR}/opaque.c)
set(OPAQUE_IDL_HDR ${IDL_OUTPUT_DIR}/opaque.h)
set(SECURITY_IDL_SRC ${IDL_OUTPUT_DIR}/security.c)
set(SECURITY_IDL_HDR ${IDL_OUTPUT_DIR}/security.h)
set(UDS_DTC_IDL_SRC ${IDL_OUTPUT_DIR}/uds-dtc.c)
set(UDS_DTC_IDL_HDR ${IDL_OUTPUT_DIR}/uds-dtc.h)

# Compile IDL files
# Note: -f keylist forces #pragma keylist handling, allowing mix of @bit_bound and #pragma keylist
add_custom_command(
    OUTPUT ${TYPES_IDL_SRC} ${TYPES_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c ${TYPES_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${TYPES_IDL}
    COMMENT "Compiling types.idl"
)

add_custom_command(
    OUTPUT ${VSS_SIGNAL_IDL_SRC} ${VSS_SIGNAL_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c -I${VEP_SCHEMA_IDL_DIR} ${VSS_SIGNAL_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${VSS_SIGNAL_IDL} ${TYPES_IDL_HDR}
    COMMENT "Compiling vss-signal.idl"
)

add_custom_command(
    OUTPUT ${AVTP_IDL_SRC} ${AVTP_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c -I${VEP_SCHEMA_IDL_DIR} ${AVTP_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${AVTP_IDL} ${TYPES_IDL_HDR}
    COMMENT "Compiling avtp.idl"
)

add_custom_command(
    OUTPUT ${OTEL_METRICS_IDL_SRC} ${OTEL_METRICS_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c -I${VEP_SCHEMA_IDL_DIR} ${OTEL_METRICS_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${OTEL_METRICS_IDL} ${TYPES_IDL_HDR}
    COMMENT "Compiling otel-metrics.idl"
)

add_custom_command(
    OUTPUT ${OTEL_LOGS_IDL_SRC} ${OTEL_LOGS_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c -I${VEP_SCHEMA_IDL_DIR} ${OTEL_LOGS_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${OTEL_LOGS_IDL} ${TYPES_IDL_HDR}
    COMMENT "Compiling otel-logs.idl"
)

add_custom_command(
    OUTPUT ${DIAGNOSTICS_IDL_SRC} ${DIAGNOSTICS_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c -I${VEP_SCHEMA_IDL_DIR} ${DIAGNOSTICS_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${DIAGNOSTICS_IDL} ${TYPES_IDL_HDR}
    COMMENT "Compiling diagnostics.idl"
)

add_custom_command(
    OUTPUT ${EVENTS_IDL_SRC} ${EVENTS_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c -I${VEP_SCHEMA_IDL_DIR} ${EVENTS_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${EVENTS_IDL} ${TYPES_IDL_HDR} ${VSS_SIGNAL_IDL_HDR}
    COMMENT "Compiling events.idl"
)

add_custom_command(
    OUTPUT ${OPAQUE_IDL_SRC} ${OPAQUE_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c -I${VEP_SCHEMA_IDL_DIR} ${OPAQUE_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${OPAQUE_IDL} ${TYPES_IDL_HDR}
    COMMENT "Compiling opaque.idl"
)

add_custom_command(
    OUTPUT ${SECURITY_IDL_SRC} ${SECURITY_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c -I${VEP_SCHEMA_IDL_DIR} ${SECURITY_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${SECURITY_IDL} ${TYPES_IDL_HDR}
    COMMENT "Compiling security.idl"
)

add_custom_command(
    OUTPUT ${UDS_DTC_IDL_SRC} ${UDS_DTC_IDL_HDR}
    COMMAND ${IDLC_EXECUTABLE} -f keylist -l c -I${VEP_SCHEMA_IDL_DIR} ${UDS_DTC_IDL}
    WORKING_DIRECTORY ${IDL_OUTPUT_DIR}
    DEPENDS ${UDS_DTC_IDL} ${TYPES_IDL_HDR}
    COMMENT "Compiling uds-dtc.idl"
)

# VEP IDL library - all IDL types in one library
add_library(vep_idl STATIC
    ${TYPES_IDL_SRC}
    ${VSS_SIGNAL_IDL_SRC}
    ${AVTP_IDL_SRC}
    ${OTEL_METRICS_IDL_SRC}
    ${OTEL_LOGS_IDL_SRC}
    ${DIAGNOSTICS_IDL_SRC}
    ${EVENTS_IDL_SRC}
    ${OPAQUE_IDL_SRC}
    ${SECURITY_IDL_SRC}
    ${UDS_DTC_IDL_SRC}
)
set_target_properties(vep_idl PROPERTIES LINKER_LANGUAGE C)
target_include_directories(vep_idl PUBLIC ${IDL_OUTPUT_DIR})
target_link_libraries(vep_idl PUBLIC CycloneDDS::ddsc)

add_custom_target(generate_idl DEPENDS
    ${TYPES_IDL_SRC} ${TYPES_IDL_HDR}
    ${VSS_SIGNAL_IDL_SRC} ${VSS_SIGNAL_IDL_HDR}
    ${AVTP_IDL_SRC} ${AVTP_IDL_HDR}
    ${OTEL_METRICS_IDL_SRC} ${OTEL_METRICS_IDL_HDR}
    ${OTEL_LOGS_IDL_SRC} ${OTEL_LOGS_IDL_HDR}
    ${DIAGNOSTICS_IDL_SRC} ${DIAGNOSTICS_IDL_HDR}
    ${EVENTS_IDL_SRC} ${EVENTS_IDL_HDR}
    ${OPAQUE_IDL_SRC} ${OPAQUE_IDL_HDR}
    ${SECURITY_IDL_SRC} ${SECURITY_IDL_HDR}
    ${UDS_DTC_IDL_SRC} ${UDS_DTC_IDL_HDR}
)
add_dependencies(vep_idl generate_idl)

# Aliases for backward compatibility
add_library(telemetry_idl ALIAS vep_idl)

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
# Component 6: covesa-ifex-core (optional, standalone IFEX services)
# ==============================================================================
if(EXISTS ${COMPONENTS_DIR}/covesa-ifex-core/CMakeLists.txt)
    message(STATUS "Adding covesa-ifex-core")
    set(BUILD_CORE ON CACHE BOOL "" FORCE)
    set(BUILD_REFERENCE_SERVICES ON CACHE BOOL "" FORCE)
    set(BUILD_TEST_SERVICES ON CACHE BOOL "" FORCE)
    set(BUILD_INTEGRATION_TESTS ${VEP_BUILD_TESTS} CACHE BOOL "" FORCE)
    add_subdirectory(${COMPONENTS_DIR}/covesa-ifex-core ${CMAKE_BINARY_DIR}/covesa-ifex-core)
else()
    message(STATUS "covesa-ifex-core not found, skipping (optional)")
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
if(EXISTS ${COMPONENTS_DIR}/covesa-ifex-core/CMakeLists.txt)
message(STATUS "  - covesa-ifex-core")
endif()
message(STATUS "")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "Tests: ${VEP_BUILD_TESTS}")
message(STATUS "Examples: ${VEP_BUILD_EXAMPLES}")
message(STATUS "")
