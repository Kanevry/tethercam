# shared/ — MIT-licensed C core shared by obs-plugin/ and tools/.
# Deliberately free of Apple frameworks so it builds and tests on Linux CI.
cmake_minimum_required(VERSION 3.16)
project(iucm_shared C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

# Opt-in sanitizer configuration: cmake -S shared -B shared/build-asan -DIUCM_SANITIZE=ON
# Applies to the library and every test target, hence add_compile_options (directory
# scope) rather than a per-target flag list.
option(IUCM_SANITIZE "Build with AddressSanitizer + UndefinedBehaviorSanitizer" OFF)
# Which sanitizers. Kept configurable because the Apple clang 17 ASan runtime
# deadlocks during its own init on macOS 26 (Darwin 25.x): the shadow-memory setup
# re-enters libsystem_malloc and spins in StaticSpinMutex::LockSlow before main().
# That hangs any -fsanitize=address binary on such a host, so those runs use
# -DIUCM_SANITIZE_LIST=undefined until a fixed runtime is available.
set(IUCM_SANITIZE_LIST "address,undefined" CACHE STRING
    "Comma-separated -fsanitize= list used when IUCM_SANITIZE=ON")
if(IUCM_SANITIZE)
    if(MSVC)
        message(FATAL_ERROR "IUCM_SANITIZE is only wired up for clang/gcc")
    endif()
    message(STATUS "iucm: sanitizers = ${IUCM_SANITIZE_LIST}")
    add_compile_options(-fsanitize=${IUCM_SANITIZE_LIST} -fno-omit-frame-pointer
                        -fno-sanitize-recover=all -g -O1)
    add_link_options(-fsanitize=${IUCM_SANITIZE_LIST})
endif()

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

foreach(test_name frame_parser frame_parser_fuzz usbmux_plist)
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
