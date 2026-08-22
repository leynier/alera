# Copies cargo's alera.exe into the CMake build tree so cmake_install does
# not have to read the short subst drive used as CARGO_TARGET_DIR.
if(NOT DEFINED ALERA_SIDECAR_HOST OR NOT DEFINED ALERA_SIDECAR_TRIPLE OR NOT DEFINED ALERA_SIDECAR_STAGED)
  message(FATAL_ERROR "stage_alera_sidecar.cmake requires ALERA_SIDECAR_HOST, ALERA_SIDECAR_TRIPLE, and ALERA_SIDECAR_STAGED")
endif()

if(EXISTS "${ALERA_SIDECAR_HOST}")
  set(ALERA_SIDECAR_SOURCE "${ALERA_SIDECAR_HOST}")
elseif(EXISTS "${ALERA_SIDECAR_TRIPLE}")
  set(ALERA_SIDECAR_SOURCE "${ALERA_SIDECAR_TRIPLE}")
else()
  message(FATAL_ERROR "alera.exe sidecar missing after cargo build. Looked for:\n  ${ALERA_SIDECAR_HOST}\n  ${ALERA_SIDECAR_TRIPLE}")
endif()

get_filename_component(ALERA_SIDECAR_STAGED_DIR "${ALERA_SIDECAR_STAGED}" DIRECTORY)
file(MAKE_DIRECTORY "${ALERA_SIDECAR_STAGED_DIR}")
execute_process(
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${ALERA_SIDECAR_SOURCE}" "${ALERA_SIDECAR_STAGED}"
  RESULT_VARIABLE ALERA_SIDECAR_COPY_RESULT
)
if(NOT ALERA_SIDECAR_COPY_RESULT EQUAL 0)
  message(FATAL_ERROR "Failed to stage sidecar from ${ALERA_SIDECAR_SOURCE} to ${ALERA_SIDECAR_STAGED}")
endif()
message(STATUS "Staged sidecar ${ALERA_SIDECAR_SOURCE} -> ${ALERA_SIDECAR_STAGED}")
