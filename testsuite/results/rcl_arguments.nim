##  Copyright 2018 Open Source Robotics Foundation, Inc.
##  START
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
  ##    Return a rcl_arguments_t struct with members initialized to `NULL`.
_Static_assert(sizeof(((constructrcutils_error_string_t))) ==
    (768 + (1024 - 768 - 20 - 6 - 1) + 20 + 6 + 1), "Maximum length calculations incorrect")
type

  rcl_arguments_impl_t* = rcl_arguments_impl_s

  rcl_arguments_t* {.importc: "rcl_arguments_t", header: "rcl_arguments.h", bycopy.} = object ##
                              ##  Hold output of parsing command line arguments.
    impl* {.importc: "impl".}: ptr rcl_arguments_impl_t ##
                              ##  Private implementation pointer.


const
  RCL_ROS_ARGS_FLAG* = "--ros-args" ##  The command-line flag that delineates the start of ROS arguments.
  RCL_ROS_ARGS_EXPLICIT_END_TOKEN* = "--" ##  The token that delineates the explicit end of ROS arguments.
  RCL_PARAM_FLAG* = "--param"   ##  The ROS flag that precedes the setting of a ROS parameter.
  RCL_SHORT_PARAM_FLAG* = "-p"  ##  The short version of the ROS flag that precedes the setting of a ROS parameter.
  RCL_PARAM_FILE_FLAG* = "--params-file" ##  The ROS flag that precedes a path to a file containing ROS parameters.
  RCL_REMAP_FLAG* = "--remap"   ##  The ROS flag that precedes a ROS remapping rule.
  RCL_SHORT_REMAP_FLAG* = "-r"  ##  The short version of the ROS flag that precedes a ROS remapping rule.
  RCL_ENCLAVE_FLAG* = "--enclave" ##  The ROS flag that precedes the name of a ROS security enclave.
  RCL_SHORT_ENCLAVE_FLAG* = "-e" ##  The short version of the ROS flag that precedes the name of a ROS security enclave.
  RCL_LOG_LEVEL_FLAG* = "--log-level" ##  The ROS flag that precedes the ROS logging level to set.
  RCL_EXTERNAL_LOG_CONFIG_FLAG* = "--log-config-file" ##
                              ##  The ROS flag that precedes the name of a configuration file to configure logging.
  RCL_LOG_STDOUT_FLAG_SUFFIX* = "stdout-logs" ##  The suffix of the ROS flag to enable or disable stdout
                                           ##  logging (must be preceded with --enable- or --disable-).
  RCL_LOG_ROSOUT_FLAG_SUFFIX* = "rosout-logs" ##  The suffix of the ROS flag to enable or disable rosout
                                           ##  logging (must be preceded with --enable- or --disable-).
  RCL_LOG_EXT_LIB_FLAG_SUFFIX* = "external-lib-logs" ##  The suffix of the ROS flag to enable or disable external library
                                                  ##  logging (must be preceded with --enable- or --disable-).


proc rcl_get_zero_initialized_arguments*(): rcl_arguments_t {.
    importc: "rcl_get_zero_initialized_arguments", header: "rcl_arguments.h".}
  ##    Return a rcl_arguments_t struct with members initialized to `NULL`.

proc rcl_parse_arguments*(argc: cint; argv: cstringArray; allocator: rcl_allocator_t;
                         args_output: ptr rcl_arguments_t): rcl_ret_t {.
    importc: "rcl_parse_arguments", header: "rcl_arguments.h".}
  ##  Parse command line arguments into a structure usable by code.
  ##
  ##  \sa rcl_get_zero_initialized_arguments()
  ##
  ##  ROS arguments are expected to be scoped by a leading `--ros-args` flag and a trailing double
  ##  dash token `--` which may be elided if no non-ROS arguments follow after the last `--ros-args`.
  ##
  ##  Remap rule parsing is supported via `-r/--remap` flags e.g. `--remap from:=to` or `-r from:=to`.
  ##  Successfully parsed remap rules are stored in the order they were given in `argv`.
  ##  If given arguments `{"__ns:=/foo", "__ns:=/bar"}` then the namespace used by nodes in this
  ##  process will be `/foo` and not `/bar`.
  ##
  ##  \sa rcl_remap_topic_name()
  ##  \sa rcl_remap_service_name()
  ##  \sa rcl_remap_node_name()
  ##  \sa rcl_remap_node_namespace()
  ##
  ##  Parameter override rule parsing is supported via `-p/--param` flags e.g. `--param name:=value`
  ##  or `-p name:=value`.
  ##
  ##

proc rcl_arguments_get_count_unparsed*(args: ptr rcl_arguments_t): cint {.
    importc: "rcl_arguments_get_count_unparsed", header: "rcl_arguments.h".}
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
                              allocator: rcl_allocator_t; nonros_argc: ptr cint;
                              nonros_argv: ptr cstringArray): rcl_ret_t {.
    importc: "rcl_remove_ros_arguments", header: "rcl_arguments.h".}

proc rcl_arguments_get_log_levels*(arguments: ptr rcl_arguments_t;
                                  log_levels: ptr rcl_log_levels_t): rcl_ret_t {.
    importc: "rcl_arguments_get_log_levels", header: "rcl_arguments.h".}

proc rcl_arguments_copy*(args: ptr rcl_arguments_t; args_out: ptr rcl_arguments_t): rcl_ret_t {.
    importc: "rcl_arguments_copy", header: "rcl_arguments.h".}

proc rcl_arguments_fini*(args: ptr rcl_arguments_t): rcl_ret_t {.
    importc: "rcl_arguments_fini", header: "rcl_arguments.h".}