cmake_minimum_required(VERSION 4.0)
project(stackbuilder NONE)

include(ExternalProject)
find_package(Git REQUIRED)

set(STACK_ORG "hyprwm" CACHE STRING "The root of all evil")
set(STACK_BASE_URL "https://github.com/${STACK_ORG}" CACHE STRING "GitHub base URL")
if(NOT DEFINED STACK_ROOT_PACKAGE)
  set(STACK_ROOT_PACKAGE "hyprland")
endif()
set(STACK_PREFIX "${CMAKE_SOURCE_DIR}/install" CACHE PATH "Install path for bin/ lib/ share/ etc.")
set(STACK_ROOT "${CMAKE_BINARY_DIR}/stack" CACHE PATH "Root directory for repos")

file(MAKE_DIRECTORY "${STACK_ROOT}")

set(STACK_META "${STACK_ROOT}/meta")
set(REPO_LIST "${STACK_META}/repo_list.json")

set(STACK_ENV
    "CLICOLOR_FORCE=1"
    "PKG_CONFIG_PATH=${STACK_PREFIX}/lib/pkgconfig:${STACK_PREFIX}/lib64/pkgconfig:${STACK_PREFIX}/share/pkgconfig:$ENV{PKG_CONFIG_PATH}"
    "CMAKE_PREFIX_PATH=${STACK_PREFIX}:$ENV{CMAKE_PREFIX_PATH}"
    "PATH=${STACK_PREFIX}/bin:$ENV{PATH}"
    "LD_LIBRARY_PATH=${STACK_PREFIX}/lib:${STACK_PREFIX}/lib64:$ENV{LD_LIBRARY_PATH}"
)

set(STACK_CMAKE_ARGS
    -G Ninja
    -DCMAKE_COLOR_DIAGNOSTICS=ON
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_COMPILER_LAUNCHER=ccache
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
    -DCMAKE_INSTALL_PREFIX=${STACK_PREFIX}
    -DCMAKE_PREFIX_PATH=${STACK_PREFIX}
    -DCMAKE_INSTALL_RPATH=${STACK_PREFIX}/lib:${STACK_PREFIX}/lib64
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
)

# It's a bit confusing. ON means log to file, ie hide the shit
option(LOG_FAILURE "Hide failures" OFF)
option(LOG_ALL "Print everything" OFF)
option(LOG_CONFIGURE "Hide configure stage" OFF)
option(LOG_BUILD "Hide what compiler is doing" ON)
option(LOG_INSTALL "Hide install locations" ON)
option(LOG_DOWNLOAD "Hide downloads" ON)
option(LOG_UPDATE "Hide updates (ugh. always.)" ON)

set(STACK_LOG_ARGS)
foreach(step DOWNLOAD UPDATE CONFIGURE BUILD INSTALL)
    if(LOG_${step} OR LOG_ALL)
        list(APPEND STACK_LOG_ARGS LOG_${step} 1)
    endif()
endforeach()
if(LOG_FAILURE OR LOG_ALL)
    list(APPEND STACK_LOG_ARGS LOG_OUTPUT_ON_FAILURE 1)
endif()

if(NOT EXISTS "${REPO_LIST}")
  message(STATUS "Fetching repo list")
  file(DOWNLOAD "https://api.github.com/orgs/${STACK_ORG}/repos?per_page=100" "${REPO_LIST}" TIMEOUT 10 STATUS status)
  list(GET status 0 status_code)
  if(NOT status_code EQUAL "0")
    message(FATAL_ERROR "Failed to fetch repo list")
  endif()
endif()

if(FETCH_REPOS_ONLY)
  unset(FETCH_REPOS_ONLY CACHE)
  return()
endif()

function(get_json_field JSON FIELD OUT)
  string(JSON len LENGTH "${${JSON}}")
  if(len GREATER 0)
    math(EXPR max_index "${len} - 1")
    set(ret "")
    foreach(i RANGE ${max_index})
      string(JSON item GET "${${JSON}}" ${i} ${FIELD})
      list(APPEND ret "${item}")
    endforeach()

    set(${OUT} "${ret}" PARENT_SCOPE)
  else()
    message(FATAL_ERROR "Can't find field ${FIELD} in the json passed to get_json_field.")
  endif()
endfunction()

file(READ "${REPO_LIST}" REPO_JSON)
get_json_field(REPO_JSON "name" REPOS)

function(clone_repo REPO)
  set(dir "${STACK_ROOT}/${REPO}")

  string(TOLOWER "${REPO}" repo_lower)
  
  get_cmake_property(var_names VARIABLES)
  
  set(target_pr "")
  foreach(original_var IN LISTS var_names)
    string(TOLOWER "${original_var}" var_lower)
    if(var_lower STREQUAL repo_lower)
      if(DEFINED CACHE{${original_var}})
        set(target_pr "${${original_var}}")
        break()
      elseif(DEFINED ${original_var})
        set(target_pr "${${original_var}}")
        break()
      endif()
    endif()
  endforeach()

  if(NOT EXISTS "${dir}/.git")
    message(STATUS "Cloning ${REPO}...")
    execute_process(COMMAND ${GIT_EXECUTABLE} clone "${STACK_BASE_URL}/${REPO}.git" "${dir}" RESULT_VARIABLE res)
    if(NOT res EQUAL 0)
      message(FATAL_ERROR "Failed to clone ${REPO}")
    endif()
  endif()

  if(target_pr AND target_pr MATCHES "^[0-9]+$")
    execute_process(
      COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
      WORKING_DIRECTORY "${dir}"
      OUTPUT_VARIABLE current_branch
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    if(current_branch STREQUAL "pr-${target_pr}")
      message(STATUS "Already on PR #${target_pr} for ${REPO}, pulling latest...")
      execute_process(
        COMMAND ${GIT_EXECUTABLE} pull origin "pull/${target_pr}/head"
        WORKING_DIRECTORY "${dir}"
        RESULT_VARIABLE pull_res
      )
    else()
      message(STATUS "Checking out PR #${target_pr} for ${REPO}...")
      execute_process(
        COMMAND ${GIT_EXECUTABLE} fetch origin "pull/${target_pr}/head:pr-${target_pr}" --force
        WORKING_DIRECTORY "${dir}"
        RESULT_VARIABLE fetch_res
      )
      if(fetch_res EQUAL 0)
        execute_process(
          COMMAND ${GIT_EXECUTABLE} checkout "pr-${target_pr}"
          WORKING_DIRECTORY "${dir}"
          RESULT_VARIABLE co_res
        )
        if(NOT co_res EQUAL 0)
          message(FATAL_ERROR "Failed to checkout PR #${target_pr} for ${REPO}")
        endif()
      else()
        message(FATAL_ERROR "Failed to fetch PR #${target_pr} for ${REPO}")
      endif()
    endif()
  endif()
endfunction()

function(get_deps REPO OUT)
  set(repo_dir "${STACK_ROOT}/${REPO}")
  set(deps "")

  if(NOT EXISTS "${repo_dir}")
    set(${OUT} "" PARENT_SCOPE)
    return()
  endif()

  file(GLOB_RECURSE cmake_files CONFIGURE_DEPENDS "${repo_dir}/CMakeLists.txt")

  foreach(cmake_file IN LISTS cmake_files)
    file(READ "${cmake_file}" content)
    string(TOLOWER "${content}" content)
    string(REGEX MATCHALL [[pkg_check_modules\([^)]*\)]] blocks "${content}")
    foreach(block IN LISTS blocks)
      string(REGEX MATCHALL "[a-z0-9_.-]+" matches "${block}")
      foreach(dep IN LISTS matches)
        string(REGEX REPLACE "[><=].*" "" dep "${dep}")
        if(dep IN_LIST VALID_REPOS AND NOT dep MATCHES "_dep$" AND NOT dep MATCHES "_version$")
          list(APPEND deps "${dep}")
        endif()
      endforeach()
    endforeach()
  endforeach()

  if(deps)
    list(REMOVE_DUPLICATES deps)
  endif()

  set(${OUT} "${deps}" PARENT_SCOPE)
endfunction()

foreach(repo IN LISTS REPOS)
  string(TOLOWER "${repo}" repo_lower)
  list(APPEND VALID_REPOS "${repo_lower}")
endforeach()

function(resolve_build_order REPO)
  if(REPO IN_LIST BUILD_ORDER)
    return()
  endif()

  clone_repo("${REPO}")
  get_deps("${REPO}" sub_deps)

  foreach(sub IN LISTS sub_deps)
    if(sub IN_LIST VALID_REPOS AND NOT sub STREQUAL REPO)
      resolve_build_order("${sub}")
    endif()
  endforeach()

  list(APPEND BUILD_ORDER "${REPO}")
  set(BUILD_ORDER "${BUILD_ORDER}" CACHE INTERNAL "" FORCE)
endfunction()

set(BUILD_ORDER "" CACHE INTERNAL "" FORCE)
resolve_build_order("${STACK_ROOT_PACKAGE}")

foreach(repo IN LISTS BUILD_ORDER)
  set(repo_dir "${STACK_ROOT}/${repo}")

  if(NOT EXISTS "${repo_dir}/CMakeLists.txt")
    message(STATUS "Skipping ${repo} (no CMakeLists.txt)")
    continue()
  endif()

  get_deps("${repo}" repo_sub_deps)
  set(ep_deps "")
  foreach(sub IN LISTS repo_sub_deps)
    if(sub IN_LIST BUILD_ORDER AND NOT sub STREQUAL repo)
      list(APPEND ep_deps "${sub}")
    endif()
  endforeach()

  ExternalProject_Add(${repo}
    PREFIX "${repo_dir}/ep"
    SOURCE_DIR "${repo_dir}"
    BINARY_DIR "${repo_dir}/build"
    INSTALL_DIR "${STACK_PREFIX}"
    DEPENDS ${ep_deps}
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${STACK_ENV}
      ${CMAKE_COMMAND} 
      -S "${repo_dir}" 
      -B "${repo_dir}/build"
      ${STACK_CMAKE_ARGS}
    BUILD_COMMAND ${CMAKE_COMMAND} -E env ${STACK_ENV}
      ${CMAKE_COMMAND} --build "${repo_dir}/build" --parallel
    INSTALL_COMMAND ${CMAKE_COMMAND} -E env ${STACK_ENV}
      ${CMAKE_COMMAND} --install "${repo_dir}/build"
    ${STACK_LOG_ARGS}
  )
endforeach()
