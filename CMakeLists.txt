cmake_minimum_required(VERSION 3.20)
project(tdc_demo CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# godot-cpp links the static C runtime on MSVC; everything else must match or the DLL fails to link.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

add_library(tdc_sim STATIC sim/src/battle.cpp)
target_include_directories(tdc_sim PUBLIC sim/include)
# Apple clang fuses a*b+c into one FMA on arm64 by default, which changes the last bits of every battle. Keep the
# rounding of the other builds.
if(APPLE)
  target_compile_options(tdc_sim PUBLIC -ffp-contract=off)
endif()

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
  if(APPLE)
    target_link_options(tdc_demo PRIVATE -Wl,-x -Wl,-dead_strip)   # Apple's linker has no -s: strip local symbols
  elseif(NOT MSVC)
    target_link_options(tdc_demo PRIVATE -s)
  endif()
endif()
