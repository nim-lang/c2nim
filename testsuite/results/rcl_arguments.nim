##  Copyright 2018 Open Source Robotics Foundation, Inc.
##  @file

import
  rcl/allocator, rcl/log_level, rcl/macros, rcl/types, rcl/visibility_control,
  rcl_yaml_param_parser/types

type

  RCUTILS_LOG_SEVERITY* {.size: sizeof(cint).} = enum
    RCUTILS_LOG_SEVERITY_UNSET = 0, ## < The unset log level
    RCUTILS_LOG_SEVERITY_DEBUG = 10, ## < The debug log level
    RCUTILS_LOG_SEVERITY_INFO = 20, ## < The info log level
    RCUTILS_LOG_SEVERITY_WARN = 30, ## < The warn log level
    RCUTILS_LOG_SEVERITY_ERROR = 40, ## < The error log level
    RCUTILS_LOG_SEVERITY_FATAL = 50 ## < The fatal log level


##  The names of severity levels.


proc rcl_get_zero_initialized_arguments*(): rcl_arguments_t {.
    importc: "rcl_get_zero_initialized_arguments", header: "rcl_arguments.h".}
  ##
                              ##    Return a rcl_arguments_t struct with members initialized to `NULL`.
_Static_assert(sizeof(((constructrcutils_error_string_t))) ==
    (768 + (1024 - 768 - 20 - 6 - 1) + 20 + 6 + 1),
               "Maximum length calculations incorrect")
type

  rcl_arguments_impl_t* = rcl_arguments_impl_s

  rcl_arguments_t* {.importc: "rcl_arguments_t", header: "rcl_arguments.h",
                     bycopy.} = object ##  Hold output of parsing command line arguments.
    impl* {.importc: "impl".}: ptr rcl_arguments_impl_t ##
                              ##  Private implementation pointer.


const
  RCL_ROS_ARGS_FLAG* = "--ros-args" ##  The command-line flag that delineates the start of ROS arguments.
  RCL_LOG_EXT_LIB_FLAG_SUFFIX* = "external-lib-logs" ##
                              ##  The suffix of the ROS flag to enable or disable external library
                              ##  logging (must be preceded with --enable- or --disable-).


proc rcl_get_zero_initialized_arguments*(): rcl_arguments_t {.
    importc: "rcl_get_zero_initialized_arguments", header: "rcl_arguments.h".}
  ##
                              ##    Return a rcl_arguments_t struct with members initialized to `NULL`.

proc rcl_parse_arguments*(argc: cint; argv: cstringArray;
                          allocator: rcl_allocator_t;
                          args_output: ptr rcl_arguments_t): rcl_ret_t {.
    importc: "rcl_parse_arguments", header: "rcl_arguments.h".}
  ##
                              ##  Parse command line arguments into a structure usable by code.
                              ##
                              ##  \sa rcl_get_zero_initialized_arguments()
                              ##
                              ##

proc rcl_arguments_get_count_unparsed*(args: ptr rcl_arguments_t): cint {.
    importc: "rcl_arguments_get_count_unparsed", header: "rcl_arguments.h".}
  ##
                              ##  Return the number of arguments that were not ROS specific arguments.
                              ##
                              ##

proc rcl_arguments_get_unparsed*(args: ptr rcl_arguments_t;
                                 allocator: rcl_allocator_t;
                                 output_unparsed_indices: ptr ptr cint): rcl_ret_t {.
    importc: "rcl_arguments_get_unparsed", header: "rcl_arguments.h".}

proc rcl_arguments_get_count_unparsed_ros*(args: ptr rcl_arguments_t): cint {.
    importc: "rcl_arguments_get_count_unparsed_ros", header: "rcl_arguments.h".}

proc rcl_arguments_get_unparsed_ros*(args: ptr rcl_arguments_t;
                                     allocator: rcl_allocator_t;
                                     output_unparsed_ros_indices: ptr ptr cint): rcl_ret_t {.
    importc: "rcl_arguments_get_unparsed_ros", header: "rcl_arguments.h".}

proc rcl_arguments_get_param_files_count*(args: ptr rcl_arguments_t): cint {.
    importc: "rcl_arguments_get_param_files_count", header: "rcl_arguments.h".}

proc rcl_arguments_get_param_files*(arguments: ptr rcl_arguments_t;
                                    allocator: rcl_allocator_t;
                                    parameter_files: ptr cstringArray): rcl_ret_t {.
    importc: "rcl_arguments_get_param_files", header: "rcl_arguments.h".}

proc rcl_arguments_get_param_overrides*(arguments: ptr rcl_arguments_t;
    parameter_overrides: ptr ptr rcl_params_t): rcl_ret_t {.
    importc: "rcl_arguments_get_param_overrides", header: "rcl_arguments.h".}

proc rcl_remove_ros_arguments*(argv: cstringArray; args: ptr rcl_arguments_t;
                               allocator: rcl_allocator_t;
                               nonros_argc: ptr cint;
                               nonros_argv: ptr cstringArray): rcl_ret_t {.
    importc: "rcl_remove_ros_arguments", header: "rcl_arguments.h".}

proc rcl_arguments_get_log_levels*(arguments: ptr rcl_arguments_t;
                                   log_levels: ptr rcl_log_levels_t): rcl_ret_t {.
    importc: "rcl_arguments_get_log_levels", header: "rcl_arguments.h".}

proc rcl_arguments_copy*(args: ptr rcl_arguments_t;
                         args_out: ptr rcl_arguments_t): rcl_ret_t {.
    importc: "rcl_arguments_copy", header: "rcl_arguments.h".}

proc rcl_arguments_fini*(args: ptr rcl_arguments_t): rcl_ret_t {.
    importc: "rcl_arguments_fini", header: "rcl_arguments.h".}