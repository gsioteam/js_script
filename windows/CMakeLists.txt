cmake_minimum_required(VERSION 3.15)
set(PROJECT_NAME "js_script")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "js_script_plugin")

add_subdirectory(quickjs)

add_library(${PLUGIN_NAME} SHARED
  "js_script_plugin.cpp"
)
target_link_libraries(
  ${PLUGIN_NAME}

  qjs
)
apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# List of absolute paths to libraries that should be bundled with the plugin
set(js_script_bundled_libraries
  ""
  PARENT_SCOPE
)
