// Copyright 2018 Open Source Robotics Foundation, Inc.

/// @file

#ifndef RCL__ARGUMENTS_H_
#define RCL__ARGUMENTS_H_

#include "rcl/allocator.h"
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
