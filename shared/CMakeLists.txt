# shared/ — MIT-licensed C core shared by obs-plugin/ and tools/.
# Deliberately free of Apple frameworks so it builds and tests on Linux CI.
cmake_minimum_required(VERSION 3.16)
project(iucm_shared C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

add_library(iucm_shared STATIC
    frame_parser.c
    usbmux.c
)
target_include_directories(iucm_shared PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

if(MSVC)
    target_compile_options(iucm_shared PRIVATE /W4 /WX)
else()
    target_compile_options(iucm_shared PRIVATE -Wall -Wextra -Werror)
endif()

enable_testing()

set(IUCM_FIXTURE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/tests/fixtures")

foreach(test_name frame_parser usbmux_plist)
    add_executable(test_${test_name} tests/test_${test_name}.c)
    target_link_libraries(test_${test_name} PRIVATE iucm_shared)
    target_compile_definitions(test_${test_name}
        PRIVATE FIXTURE_DIR="${IUCM_FIXTURE_DIR}")
    if(MSVC)
        target_compile_options(test_${test_name} PRIVATE /W4 /WX)
    else()
        target_compile_options(test_${test_name} PRIVATE -Wall -Wextra -Werror)
    endif()
    add_test(NAME ${test_name} COMMAND test_${test_name})
endforeach()
