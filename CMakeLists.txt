cmake_minimum_required(VERSION 3.20)
project(tdc_demo CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_library(tdc_sim STATIC sim/src/battle.cpp)
target_include_directories(tdc_sim PUBLIC sim/include)

option(TDC_TESTS "Build the rules tests" ON)
if(TDC_TESTS)
  enable_testing()
  add_executable(tdc_tests sim/tests/tests.cpp)
  target_link_libraries(tdc_tests tdc_sim)
  add_test(NAME rules COMMAND tdc_tests)
endif()

option(TDC_EXTENSION "Build the Godot extension" ON)
if(TDC_EXTENSION)
  add_subdirectory(extension/godot-cpp)
  add_library(tdc_demo SHARED extension/src/demo_battle.cpp extension/src/register_types.cpp)
  target_link_libraries(tdc_demo PRIVATE tdc_sim godot-cpp)
  # Strip symbols and hide everything but the entry point: less for anyone reading the binary.
  set_target_properties(tdc_demo PROPERTIES CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON
                        LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/game/bin RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/game/bin
                        LIBRARY_OUTPUT_DIRECTORY_RELEASE ${CMAKE_SOURCE_DIR}/game/bin RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_SOURCE_DIR}/game/bin)
  if(NOT MSVC)
    target_link_options(tdc_demo PRIVATE -s)
  endif()
endif()
