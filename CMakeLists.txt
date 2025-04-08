cmake_minimum_required(VERSION 3.10)

project(libBWM)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)
set(CMAKE_OSX_DEPLOYMENT_TARGET "10.14")
set(CMAKE_OSX_ARCHITECTURES "arm64;arm64e;x86_64")

# Build dylib from Objective-C source in remote/
file(GLOB_RECURSE REMOTE_SRC "remote/*.m")
add_library(bwm_remote SHARED ${REMOTE_SRC})
target_link_libraries(bwm_remote "-framework AppKit")

file(GLOB_RECURSE PROGRAM_SRC "program/*.m")
add_library(bwm SHARED ${PROGRAM_SRC})

# Optional: Include headers from 'remote/' or other dirs
target_include_directories(bwm PRIVATE remote)
target_link_libraries(bwm
    "-framework AppKit"
    "-F/System/Library/PrivateFrameworks"
    "-framework Skylight"
)

# Move built dylib to /private/var/ammonia/core/tweaks
add_custom_command(TARGET bwm_remote POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory /private/var/ammonia/core/tweaks/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:bwm_remote> /private/var/ammonia/core/tweaks/
    COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:bwm> /private/var/ammonia/core/tweaks/
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_SOURCE_DIR}/libbwm_remote.dylib.blacklist /private/var/ammonia/core/tweaks/
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_SOURCE_DIR}/libbwm.dylib.blacklist /private/var/ammonia/core/tweaks/
    COMMENT "Moving built dylib to /private/var/ammonia/core/tweaks"
)