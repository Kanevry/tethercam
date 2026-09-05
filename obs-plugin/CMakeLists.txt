# obs-iphone-usb-cam — OBS source plugin (GPL-2.0-or-later).
# Based on obs-plugintemplate. Links the MIT-licensed C core from ../shared
# by compiling its sources directly into the module (no add_subdirectory, so the
# shared/ ctest targets do not leak into the Xcode project).
cmake_minimum_required(VERSION 3.28...3.30)

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/common/bootstrap.cmake" NO_POLICY_SCOPE)

project(${_name} VERSION ${_version})

option(ENABLE_FRONTEND_API "Use obs-frontend-api for UI functionality" OFF)
option(ENABLE_QT "Use Qt functionality" OFF)

if(NOT APPLE)
  message(FATAL_ERROR "obs-iphone-usb-cam is macOS-only (VideoToolbox + usbmuxd).")
endif()

# ObjC/ObjC++ must be enabled before target_sources() sees .m/.mm files.
enable_language(OBJC)
enable_language(OBJCXX)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED TRUE)

include(compilerconfig)
include(defaults)
include(helpers)

add_library(${CMAKE_PROJECT_NAME} MODULE)

find_package(libobs REQUIRED)
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE OBS::libobs)

set(IUCM_SHARED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../shared")
if(NOT EXISTS "${IUCM_SHARED_DIR}/frame_parser.c")
  message(FATAL_ERROR "shared/ not found at ${IUCM_SHARED_DIR}")
endif()

target_sources(
  ${CMAKE_PROJECT_NAME}
  PRIVATE
    src/plugin-main.c
    src/hevc_decoder.h
    src/hevc_decoder.mm
    src/iphone_source.h
    src/iphone_source.mm
    "${IUCM_SHARED_DIR}/frame_parser.c"
    "${IUCM_SHARED_DIR}/usbmux.c"
)

target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE "${IUCM_SHARED_DIR}" src)

target_link_libraries(
  ${CMAKE_PROJECT_NAME}
  PRIVATE
    "$<LINK_LIBRARY:FRAMEWORK,VideoToolbox.framework>"
    "$<LINK_LIBRARY:FRAMEWORK,CoreMedia.framework>"
    "$<LINK_LIBRARY:FRAMEWORK,CoreVideo.framework>"
    "$<LINK_LIBRARY:FRAMEWORK,CoreFoundation.framework>"
    "$<LINK_LIBRARY:FRAMEWORK,Foundation.framework>"
)

set_target_properties_plugin(
  ${CMAKE_PROJECT_NAME}
  PROPERTIES
    OUTPUT_NAME ${_name}
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
)
