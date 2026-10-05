# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(Voguesly LANGUAGES CXX)

# [Voguesly] webview_windows 0.4.0 用 <experimental/coroutine>,新版 MSVC(VS18)当硬错误 STL1011;
# 全局抑制该弃用错误,令 webview_windows plugin 能编译(否则 Windows installer 打包失败)。
add_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "Voguesly")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES "EnableLoopback.exe" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# [Voguesly] webview_windows 0.4.0 把 webview_windows_bundled_libraries 设成空(见其 CMakeLists 末),
# 故 WebView2Loader.dll 只被 nuget .targets 拷到 plugin 构建夹、NOT 进最终 bundle → 在线客服 WebView2
# 运行时 initialize() 失败退外部浏览器。此处 vendor x64 loader(nuget Microsoft.Web.WebView2 1.0.1210.39)
# 并显式装进 bundle,令 in-app 客服窗真正可用。
install(FILES "WebView2Loader.dll" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# [Voguesly 0.9.85] VC++ 运行库随包部署(app-local,B-P0-WIN-VCRUNTIME-0922)。
# 全新 Win10 没有 VC++ 运行库:安装版报「找不到 VCRUNTIME140_1.dll」,便携版报「找不到 MSVCP140.dll」。
# Voguesly.exe、各插件 dll、VogueslyHelperService.exe 都依赖这 3 个(UCRT 即 api-ms-win-crt-* 系统自带,不用带)。
# 放在 CMake install 步骤而不是 workflow,原因:
#   ① 它是 `flutter build windows` 的一部分 ⇒ flutter_distributor 随后打的 exe / zip(以及本地构建)都一定带上;
#      flutter_distributor 是「构建完立即打包」,workflow 没有位置在两者之间插步骤。
#   ② DLL 取自「编译本次构建的同一套 VS」的 Redist ⇒ 版本一定 >= 编译所用工具集(app-local 部署的硬性要求)。
#   ③ 找不到就 FATAL_ERROR:宁可构建失败,也不要悄悄出一个在全新系统上打不开的包。
set(VOGUESLY_CRT_DLLS vcruntime140.dll vcruntime140_1.dll msvcp140.dll)
string(TOLOWER "${MSVC_CXX_ARCHITECTURE_ID}" _vg_crt_arch)
if(NOT _vg_crt_arch)
  set(_vg_crt_arch "x64")
endif()
set(_vg_crt_candidates "")
# 优先:开发者命令行 / vcvars 设置的 VCToolsRedistDir(例:...\VC\Redist\MSVC\14.44.35112\)
if(DEFINED ENV{VCToolsRedistDir})
  file(TO_CMAKE_PATH "$ENV{VCToolsRedistDir}" _vg_redist_env)
  file(GLOB _vg_found "${_vg_redist_env}/${_vg_crt_arch}/Microsoft.VC*.CRT/vcruntime140_1.dll")
  list(APPEND _vg_crt_candidates ${_vg_found})
endif()
# 其次:从编译器路径反推 VS 安装目录(...\VC\Tools\MSVC\<ver>\bin\Hostx64\x64\cl.exe → ...\VC\Redist\MSVC\<ver>\)
string(REGEX REPLACE "/Tools/MSVC/.*$" "" _vg_vc_dir "${CMAKE_CXX_COMPILER}")
if(EXISTS "${_vg_vc_dir}/Redist/MSVC")
  file(GLOB _vg_found "${_vg_vc_dir}/Redist/MSVC/*/${_vg_crt_arch}/Microsoft.VC*.CRT/vcruntime140_1.dll")
  list(SORT _vg_found COMPARE NATURAL ORDER DESCENDING)
  list(APPEND _vg_crt_candidates ${_vg_found})
endif()
set(VOGUESLY_CRT_DIR "")
foreach(_vg_candidate IN LISTS _vg_crt_candidates)
  get_filename_component(_vg_dir "${_vg_candidate}" DIRECTORY)
  set(_vg_all_present TRUE)
  foreach(_vg_dll IN LISTS VOGUESLY_CRT_DLLS)
    if(NOT EXISTS "${_vg_dir}/${_vg_dll}")
      set(_vg_all_present FALSE)
    endif()
  endforeach()
  if(_vg_all_present)
    set(VOGUESLY_CRT_DIR "${_vg_dir}")
    break()
  endif()
endforeach()
if(NOT VOGUESLY_CRT_DIR)
  message(FATAL_ERROR
    "[Voguesly] 找不到 VC++ 运行库(${VOGUESLY_CRT_DLLS})。"
    "请用 Visual Studio Installer 安装「MSVC C++ x64/x86 生成工具」(含 Redist),"
    "或在开发者命令行中设置 VCToolsRedistDir。compiler=${CMAKE_CXX_COMPILER}")
endif()
message(STATUS "[Voguesly] VC++ runtime (app-local) from: ${VOGUESLY_CRT_DIR}")
foreach(_vg_dll IN LISTS VOGUESLY_CRT_DLLS)
  install(FILES "${VOGUESLY_CRT_DIR}/${_vg_dll}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach()

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
