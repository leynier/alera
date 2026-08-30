cmake_minimum_required(VERSION 3.14)
project(alera_windows_runner_tests LANGUAGES CXX)

enable_testing()
add_executable(win32_single_instance_test
  "../win32_single_instance.cpp"
  "win32_single_instance_test.cpp"
)
target_include_directories(win32_single_instance_test PRIVATE "..")
target_compile_features(win32_single_instance_test PRIVATE cxx_std_17)
target_compile_definitions(win32_single_instance_test PRIVATE UNICODE _UNICODE NOMINMAX)
target_compile_options(win32_single_instance_test PRIVATE /W4 /WX /EHsc)
target_link_libraries(win32_single_instance_test PRIVATE user32)
add_test(NAME win32_single_instance COMMAND win32_single_instance_test)
set_tests_properties(win32_single_instance PROPERTIES TIMEOUT 30)
