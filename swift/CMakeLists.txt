# swift/CMakeLists.txt

cmake_minimum_required(VERSION 3.24.0)
project(LibChewingSwiftPackage NONE)

include(ExternalProject)

#
# 1) Allow the user to override TOOLCHAIN_FILE (or fall back to a default path).
#
if(NOT DEFINED TOOLCHAIN_FILE)
    if(DEFINED ENV{TOOLCHAIN_FILE})
        set(TOOLCHAIN_FILE $ENV{TOOLCHAIN_FILE})
    else()
        message(FATAL_ERROR "TOOLCHAIN_FILE is not defined. Please invoke CMake with -DTOOLCHAIN_FILE=<path to ios.toolchain.cmake>.")
    endif()
endif()

#
# 2) Configuration variables (overrideable via -D when invoking CMake)
#
set(DEPLOYMENT_TARGET "16.0" CACHE STRING "iOS deployment target (e.g. 16.0)")
set(BUILD_TYPE "Release" CACHE STRING "Build type (Release / Debug / RelWithDebInfo)")

#
# 3) Paths and directories
#
# CMAKE_SOURCE_DIR here points to swift/, so the libchewing root is one level up.
set(LIBC_ROOT_DIR "${CMAKE_SOURCE_DIR}/..") # root of libchewing
set(BUILD_BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}/build") # swift/build/
set(BUILD_IOS_DIR "${BUILD_BASE_DIR}/iphone") # swift/build/iphone
set(BUILD_SIM_ARM "${BUILD_BASE_DIR}/simulator") # swift/build/simulator (ARM64)
set(BUILD_SIM_X86 "${BUILD_BASE_DIR}/simulator-x86") # swift/build/simulator-x86
set(BUILD_SIM_FAT "${BUILD_BASE_DIR}/simulator-fat") # swift/build/simulator-fat

# Where we output the final XCFramework:
set(PACKAGE_DIR "${CMAKE_SOURCE_DIR}/../swift/chewing-simplified")
set(XCFRAMEWORK_OUTPUT "${PACKAGE_DIR}/libchewing.xcframework")

# Where to copy any *.dat files for SwiftPM resources:
set(SPM_RESOURCES_DIR "${PACKAGE_DIR}/src/Resources/data")

#
# 4) ExternalProject for each slice
#

# Build for Device (iPhone, aarch64-apple-ios)
ExternalProject_Add(libchewing_ios
    SOURCE_DIR "${LIBC_ROOT_DIR}"
    BINARY_DIR "${BUILD_IOS_DIR}"
    CMAKE_ARGS
    -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE}
    -DPLATFORM=OS64
    -DDEPLOYMENT_TARGET=${DEPLOYMENT_TARGET}
    -DCMAKE_BUILD_TYPE=${BUILD_TYPE}
    -DRust_CARGO_TARGET=aarch64-apple-ios
    -DBUILD_TESTING=off
    BUILD_COMMAND ${CMAKE_COMMAND} --build .
    INSTALL_COMMAND "" # no install steps
)

# Build for Simulator ARM64 (aarch64-apple-ios-sim)
ExternalProject_Add(libchewing_sim_arm
    SOURCE_DIR "${LIBC_ROOT_DIR}"
    BINARY_DIR "${BUILD_SIM_ARM}"
    CMAKE_ARGS
    -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE}
    -DPLATFORM=SIMULATORARM64
    -DDEPLOYMENT_TARGET=${DEPLOYMENT_TARGET}
    -DCMAKE_BUILD_TYPE=${BUILD_TYPE}
    -DRust_CARGO_TARGET=aarch64-apple-ios-sim
    -DBUILD_TESTING=off
    BUILD_COMMAND ${CMAKE_COMMAND} --build .
    INSTALL_COMMAND ""
)

# Build for Simulator x86_64
ExternalProject_Add(libchewing_sim_x86
    SOURCE_DIR "${LIBC_ROOT_DIR}"
    BINARY_DIR "${BUILD_SIM_X86}"
    CMAKE_ARGS
    -DCMAKE_TOOLCHAIN_FILE=${TOOLCHAIN_FILE}
    -DPLATFORM=SIMULATOR64
    -DDEPLOYMENT_TARGET=${DEPLOYMENT_TARGET}
    -DCMAKE_BUILD_TYPE=${BUILD_TYPE}
    -DRust_CARGO_TARGET=x86_64-apple-ios
    -DBUILD_TESTING=OFF
    BUILD_COMMAND ${CMAKE_COMMAND} --build .
    INSTALL_COMMAND ""
)

#
# 5) Once both simulator slices are built, create a "fat" simulator dylib
#
add_custom_command(
    OUTPUT "${BUILD_SIM_FAT}/libchewing.dylib"
    DEPENDS libchewing_sim_arm libchewing_sim_x86
    COMMAND ${CMAKE_COMMAND} -E make_directory "${BUILD_SIM_FAT}"
    COMMAND lipo -create
    "${BUILD_SIM_ARM}/libchewing.dylib"
    "${BUILD_SIM_X86}/libchewing.dylib"
    -output "${BUILD_SIM_FAT}/libchewing.dylib"
    COMMENT "↪ Creating fat simulator dylib at ${BUILD_SIM_FAT}/libchewing.dylib"
)

add_custom_target(create_simulator_fat
    DEPENDS "${BUILD_SIM_FAT}/libchewing.dylib"
)

# Create device framework
add_custom_command(
    OUTPUT "${BUILD_IOS_DIR}/libchewing.framework/libchewing"
    DEPENDS libchewing_ios
    COMMAND ${CMAKE_COMMAND} -E make_directory "${BUILD_IOS_DIR}/libchewing.framework/Headers"
    COMMAND ${CMAKE_COMMAND} -E copy "${BUILD_IOS_DIR}/libchewing.dylib" "${BUILD_IOS_DIR}/libchewing.framework/libchewing"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${LIBC_ROOT_DIR}/capi/include" "${BUILD_IOS_DIR}/libchewing.framework/Headers"
    COMMENT "↪ Creating iOS framework at ${BUILD_IOS_DIR}/libchewing.framework"
)
add_custom_target(libchewing_framework_ios DEPENDS "${BUILD_IOS_DIR}/libchewing.framework/libchewing")

# Create simulator framework
add_custom_command(
    OUTPUT "${BUILD_SIM_FAT}/libchewing.framework/libchewing"
    DEPENDS create_simulator_fat
    COMMAND ${CMAKE_COMMAND} -E make_directory "${BUILD_SIM_FAT}/libchewing.framework/Headers"
    COMMAND ${CMAKE_COMMAND} -E copy "${BUILD_SIM_FAT}/libchewing.dylib" "${BUILD_SIM_FAT}/libchewing.framework/libchewing"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${LIBC_ROOT_DIR}/capi/include" "${BUILD_SIM_FAT}/libchewing.framework/Headers"
    COMMENT "↪ Creating simulator framework at ${BUILD_SIM_FAT}/libchewing.framework"
)
add_custom_target(libchewing_framework_sim DEPENDS "${BUILD_SIM_FAT}/libchewing.framework/libchewing")


# 6.1) Create the modulemap
file(WRITE "${BUILD_BASE_DIR}/module.modulemap" "module CLibChewing {\n  header \"chewing-simplified.h\"\n  export *\n}\n")

# Copy module.modulemap into framework Modules
add_custom_command(TARGET libchewing_framework_ios POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${BUILD_IOS_DIR}/libchewing.framework/Modules"
    COMMAND ${CMAKE_COMMAND} -E copy "${BUILD_BASE_DIR}/module.modulemap" "${BUILD_IOS_DIR}/libchewing.framework/Modules/module.modulemap"
)
# Copy Info.plist into device framework
add_custom_command(TARGET libchewing_framework_ios POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/Info.plist" "${BUILD_IOS_DIR}/libchewing.framework/Info.plist"
)

add_custom_command(TARGET libchewing_framework_sim POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${BUILD_SIM_FAT}/libchewing.framework/Modules"
    COMMAND ${CMAKE_COMMAND} -E copy "${BUILD_BASE_DIR}/module.modulemap" "${BUILD_SIM_FAT}/libchewing.framework/Modules/module.modulemap"
)
# Copy Info.plist into simulator framework
add_custom_command(TARGET libchewing_framework_sim POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_SOURCE_DIR}/Info.plist" "${BUILD_SIM_FAT}/libchewing.framework/Info.plist"
)

#
# 6.2) Create the XCFramework once device + fat simulator are ready
#
add_custom_command(
    OUTPUT "${XCFRAMEWORK_OUTPUT}"
    DEPENDS libchewing_framework_ios libchewing_framework_sim
    COMMAND ${CMAKE_COMMAND} -E make_directory "${PACKAGE_DIR}"
    COMMAND xcodebuild -create-xcframework
    -framework "${BUILD_IOS_DIR}/libchewing.framework"
    -framework "${BUILD_SIM_FAT}/libchewing.framework"
    -output "${XCFRAMEWORK_OUTPUT}"
    COMMENT "↪ Creating libchewing.xcframework in ${PACKAGE_DIR}"
)

add_custom_target(create_xcframework
    DEPENDS "${XCFRAMEWORK_OUTPUT}"
)

#
# 7) Copy any .dat files from the build‐tree into the SwiftPM resources folder
#
add_custom_target(copy_resources ALL
    COMMAND ${CMAKE_COMMAND} -E make_directory "${SPM_RESOURCES_DIR}"
    COMMAND /usr/bin/find "${BUILD_BASE_DIR}" -name "*.dat" -exec ${CMAKE_COMMAND} -E copy_if_different {} "${SPM_RESOURCES_DIR}/" "\\;"
)

add_dependencies(copy_resources create_xcframework)

#
# 8) Top-level “all_build” target to tie everything together
#
add_custom_target(all_build
    DEPENDS create_xcframework copy_resources
)

# If you run “cmake --build .” with no target, build “all_build”
add_custom_target(default ALL
    DEPENDS all_build
)