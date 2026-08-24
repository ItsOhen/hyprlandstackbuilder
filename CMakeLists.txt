cmake_minimum_required(VERSION 3.30)
project(stackbuilder NONE)

include(ExternalProject)

set(BASE_URL "https://github.com/hyprwm")

if(NOT HYPRLAND_TAG)
  execute_process(
    COMMAND git ls-remote --tags --refs --sort=-v:refname "${BASE_URL}/hyprland.git"
    OUTPUT_VARIABLE GIT_TAGS_OUTPUT
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )
  string(REGEX MATCH "refs/tags/([^\n\r]+)" _ "${GIT_TAGS_OUTPUT}")
  if(CMAKE_MATCH_1)
    set(HYPRLAND_TAG "${CMAKE_MATCH_1}")
  else()
    set(HYPRLAND_TAG "main")
  endif()
endif()

if(NOT LOCAL_PREFIX)
  set(LOCAL_PREFIX "${CMAKE_SOURCE_DIR}/${HYPRLAND_TAG}")
endif()

set(PASSTHROUGH_ENV
    "CLICOLOR_FORCE=1"
    "PKG_CONFIG_PATH=${LOCAL_PREFIX}/lib/pkgconfig:${LOCAL_PREFIX}/share/pkgconfig:$ENV{PKG_CONFIG_PATH}"
    "CMAKE_PREFIX_PATH=${LOCAL_PREFIX}:$ENV{CMAKE_PREFIX_PATH}"
    "PATH=${LOCAL_PREFIX}/bin:$ENV{PATH}"
    "LD_LIBRARY_PATH=${LOCAL_PREFIX}/lib:$ENV{LD_LIBRARY_PATH}"
)

set(HYPR_CMAKE_ARGS
    -G Ninja
    -DCMAKE_COLOR_DIAGNOSTICS=ON
    -DCMAKE_C_COMPILER_LAUNCHER=ccache
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
    -DCMAKE_INSTALL_PREFIX=${LOCAL_PREFIX}
    -DCMAKE_PREFIX_PATH=${LOCAL_PREFIX}
    -DCMAKE_INSTALL_RPATH=${LOCAL_PREFIX}/lib
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=TRUE
    -DCMAKE_BUILD_WITH_INSTALL_RPATH=TRUE
    -DCMAKE_BUILD_TYPE=Release
)

function(add_project name)
    cmake_parse_arguments(ARG "" "TAG" "DEPENDS" ${ARGN})

    set(PROJ_TAG "main")
    if(ARG_TAG)
      set(PROJ_TAG "${ARG_TAG}")
    endif()

    ExternalProject_Add(${name}
        GIT_REPOSITORY "${BASE_URL}/${name}.git"
        GIT_TAG ${PROJ_TAG}
        DEPENDS ${ARG_DEPENDS}
        CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env ${PASSTHROUGH_ENV} 
            ${CMAKE_COMMAND} <SOURCE_DIR> ${HYPR_CMAKE_ARGS}
        BUILD_COMMAND ${CMAKE_COMMAND} -E env ${PASSTHROUGH_ENV} 
            ${CMAKE_COMMAND} --build .
        INSTALL_COMMAND ${CMAKE_COMMAND} -E env ${PASSTHROUGH_ENV} 
            ${CMAKE_COMMAND} --build . --target install
        LOG_DOWNLOAD 1
        LOG_UPDATE 1
        LOG_CONFIGURE 1
        #LOG_BUILD 1
        #LOG_INSTALL 1
        LOG_OUTPUT_ON_FAILURE 1
    )
endfunction()

# Build dep tree

add_project(hyprutils)
add_project(hyprwayland-scanner DEPENDS hyprutils)
add_project(hyprlang            DEPENDS hyprutils)
add_project(hyprwire            DEPENDS hyprutils)
add_project(aquamarine          DEPENDS hyprutils hyprwayland-scanner)
add_project(hyprgraphics        DEPENDS hyprutils aquamarine hyprwayland-scanner)
add_project(hyprcursor          DEPENDS hyprlang hyprgraphics hyprutils)
add_project(hyprland            TAG ${HYPRLAND_TAG} DEPENDS aquamarine hyprlang hyprcursor hyprutils hyprwire hyprgraphics hyprwayland-scanner)
