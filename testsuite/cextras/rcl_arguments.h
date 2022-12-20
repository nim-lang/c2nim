// Copyright 2018 Open Source Robotics Foundation, Inc.
// START

/// @file

#ifndef RCL__ARGUMENTS_H_
#define RCL__ARGUMENTS_H_

#include "rcl/allocator.h"
#include "rcl/log_level.h"
#include "rcl/macros.h"
#include "rcl/types.h"
#include "rcl/visibility_control.h"
#include "rcl_yaml_param_parser/types.h"

#ifdef __cplusplus
extern "C"
{
#endif

enum RCUTILS_LOG_SEVERITY
{
  RCUTILS_LOG_SEVERITY_UNSET = 0,  ///< The unset log level
  RCUTILS_LOG_SEVERITY_DEBUG = 10,  ///< The debug log level
  RCUTILS_LOG_SEVERITY_INFO = 20,  ///< The info log level
  RCUTILS_LOG_SEVERITY_WARN = 30,  ///< The warn log level
  RCUTILS_LOG_SEVERITY_ERROR = 40,  ///< The error log level
  RCUTILS_LOG_SEVERITY_FATAL = 50,  ///< The fatal log level
};

#pragma c2nim mergeblocks
#pragma c2nim delete g_rcutils_log_severity_names
#pragma c2nim reordercomments

// The names of severity levels.
__attribute__ ((visibility("default")))
extern const char * const g_rcutils_log_severity_names[RCUTILS_LOG_SEVERITY_FATAL + 1];

///   Return a rcl_arguments_t struct with members initialized to `NULL`.
RCL_PUBLIC
RCL_WARN_UNUSED
rcl_arguments_t
rcl_get_zero_initialized_arguments(void);

_Static_assert(sizeof((constructrcutils_error_string_t)) ==
    (768 + (1024 - 768 - 20 - 6 - 1) + 20 + 6 + 1), "Maximum length calculations incorrect");

typedef struct rcl_arguments_impl_s rcl_arguments_impl_t;

/// Hold output of parsing command line arguments.
typedef struct rcl_arguments_s
{
  /// Private implementation pointer.
  rcl_arguments_impl_t * impl;
} rcl_arguments_t;



/// The command-line flag that delineates the start of ROS arguments.
#define RCL_ROS_ARGS_FLAG "--ros-args"

/// The token that delineates the explicit end of ROS arguments.
#define RCL_ROS_ARGS_EXPLICIT_END_TOKEN "--"

/// The ROS flag that precedes the setting of a ROS parameter.
#define RCL_PARAM_FLAG "--param"

/// The short version of the ROS flag that precedes the setting of a ROS parameter.
#define RCL_SHORT_PARAM_FLAG "-p"

/// The ROS flag that precedes a path to a file containing ROS parameters.
#define RCL_PARAM_FILE_FLAG "--params-file"

/// The ROS flag that precedes a ROS remapping rule.
#define RCL_REMAP_FLAG "--remap"

/// The short version of the ROS flag that precedes a ROS remapping rule.
#define RCL_SHORT_REMAP_FLAG "-r"

/// The ROS flag that precedes the name of a ROS security enclave.
#define RCL_ENCLAVE_FLAG "--enclave"

/// The short version of the ROS flag that precedes the name of a ROS security enclave.
#define RCL_SHORT_ENCLAVE_FLAG "-e"

/// The ROS flag that precedes the ROS logging level to set.
#define RCL_LOG_LEVEL_FLAG "--log-level"

/// The ROS flag that precedes the name of a configuration file to configure logging.
#define RCL_EXTERNAL_LOG_CONFIG_FLAG "--log-config-file"

/// The suffix of the ROS flag to enable or disable stdout
/// logging (must be preceded with --enable- or --disable-).
#define RCL_LOG_STDOUT_FLAG_SUFFIX "stdout-logs"

/// The suffix of the ROS flag to enable or disable rosout
/// logging (must be preceded with --enable- or --disable-).
#define RCL_LOG_ROSOUT_FLAG_SUFFIX "rosout-logs"

/// The suffix of the ROS flag to enable or disable external library
/// logging (must be preceded with --enable- or --disable-).
#define RCL_LOG_EXT_LIB_FLAG_SUFFIX "external-lib-logs"

///   Return a rcl_arguments_t struct with members initialized to `NULL`.
RCL_PUBLIC
RCL_WARN_UNUSED
rcl_arguments_t
rcl_get_zero_initialized_arguments(void);

/// Parse command line arguments into a structure usable by code.
/**
 * \sa rcl_get_zero_initialized_arguments()
 *
 * ROS arguments are expected to be scoped by a leading `--ros-args` flag and a trailing double
 * dash token `--` which may be elided if no non-ROS arguments follow after the last `--ros-args`.
 *
 * Remap rule parsing is supported via `-r/--remap` flags e.g. `--remap from:=to` or `-r from:=to`.
 * Successfully parsed remap rules are stored in the order they were given in `argv`.
 * If given arguments `{"__ns:=/foo", "__ns:=/bar"}` then the namespace used by nodes in this
 * process will be `/foo` and not `/bar`.
 *
 * \sa rcl_remap_topic_name()
 * \sa rcl_remap_service_name()
 * \sa rcl_remap_node_name()
 * \sa rcl_remap_node_namespace()
 *
 * Parameter override rule parsing is supported via `-p/--param` flags e.g. `--param name:=value`
 * or `-p name:=value`.
 *
 */
RCL_PUBLIC
RCL_WARN_UNUSED
rcl_ret_t
rcl_parse_arguments(
  int argc,
  const char * const * argv,
  rcl_allocator_t allocator,
  rcl_arguments_t * args_output);

/// Return the number of arguments that were not ROS specific arguments.
/**
 */
RCL_ALIGNAS(8)
RCL_WARN_UNUSED
int
rcl_arguments_get_count_unparsed(
  const rcl_arguments_t * args);

RCL_PUBLIC
RCL_WARN_UNUSED
rcl_ret_t
rcl_arguments_get_unparsed(
  const rcl_arguments_t * args,
  rcl_allocator_t allocator,
  int ** output_unparsed_indices);

RCL_PUBLIC
RCL_WARN_UNUSED
int
rcl_arguments_get_count_unparsed_ros(
  const rcl_arguments_t * args);

RCL_PUBLIC
RCL_WARN_UNUSED
rcl_ret_t
rcl_arguments_get_unparsed_ros(
  const rcl_arguments_t * args,
  rcl_allocator_t allocator,
  int ** output_unparsed_ros_indices);

RCL_PUBLIC
RCL_WARN_UNUSED
int
rcl_arguments_get_param_files_count(
  const rcl_arguments_t * args);


RCL_PUBLIC
RCL_WARN_UNUSED
rcl_ret_t
rcl_arguments_get_param_files(
  const rcl_arguments_t * arguments,
  rcl_allocator_t allocator,
  char *** parameter_files);

RCL_PUBLIC
RCL_WARN_UNUSED
rcl_ret_t
rcl_arguments_get_param_overrides(
  const rcl_arguments_t * arguments,
  rcl_params_t ** parameter_overrides);

RCL_PUBLIC
RCL_WARN_UNUSED
rcl_ret_t
rcl_remove_ros_arguments(
  const char * const * argv,
  const rcl_arguments_t * args,
  rcl_allocator_t allocator,
  int * nonros_argc,
  const char *** nonros_argv);

RCL_PUBLIC
RCL_WARN_UNUSED
rcl_ret_t
rcl_arguments_get_log_levels(
  const rcl_arguments_t * arguments,
  rcl_log_levels_t * log_levels);

RCL_PUBLIC
RCL_WARN_UNUSED
rcl_ret_t
rcl_arguments_copy(
  const rcl_arguments_t * args,
  rcl_arguments_t * args_out);

RCL_PUBLIC
RCL_WARN_UNUSED
rcl_ret_t
rcl_arguments_fini(
  rcl_arguments_t * args);

#ifdef __cplusplus
}
#endif

#endif  // RCL__ARGUMENTS_H_
