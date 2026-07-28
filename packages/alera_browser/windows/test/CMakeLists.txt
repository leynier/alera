cmake_minimum_required(VERSION 3.14)
project(alera_browser_windows_tests LANGUAGES CXX)

enable_testing()

add_executable(alera_browser_windows_tests
  "../browser_import_profile_selection.cpp"
  "../browser_json.cpp"
  "browser_windows_unit_test.cpp"
)
target_compile_features(alera_browser_windows_tests PRIVATE cxx_std_17)
target_include_directories(alera_browser_windows_tests PRIVATE "..")
if(MSVC)
  target_compile_options(alera_browser_windows_tests PRIVATE /W4 /WX)
endif()

add_test(
  NAME alera_browser_windows_tests
  COMMAND alera_browser_windows_tests
)
