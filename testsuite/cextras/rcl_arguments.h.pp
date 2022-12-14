
// Copyright 2018 Open Source Robotics Foundation, Inc.
// START

// @file
typedef struct rcl_arguments_impl_s rcl_arguments_impl_t;
// Hold output of parsing command line arguments.
typedef struct rcl_arguments_s
{
// Private implementation pointer.
rcl_arguments_impl_t * impl;
} rcl_arguments_t;
// The command-line flag that delineates the start of ROS arguments.

// The token that delineates the explicit end of ROS arguments.

// The ROS flag that precedes the setting of a ROS parameter.

// The short version of the ROS flag that precedes the setting of a ROS parameter.

// The ROS flag that precedes a path to a file containing ROS parameters.

// The ROS flag that precedes a ROS remapping rule.

// The short version of the ROS flag that precedes a ROS remapping rule.

// The ROS flag that precedes the name of a ROS security enclave.

// The short version of the ROS flag that precedes the name of a ROS security enclave.

// The ROS flag that precedes the ROS logging level to set.

// The ROS flag that precedes the name of a configuration file to configure logging.

// The suffix of the ROS flag to enable or disable stdout
// logging (must be preceded with --enable- or --disable-).

// The suffix of the ROS flag to enable or disable rosout
// logging (must be preceded with --enable- or --disable-).

// The suffix of the ROS flag to enable or disable external library
// logging (must be preceded with --enable- or --disable-).

//   Return a rcl_arguments_t struct with members initialized to `NULL`.
__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_arguments_t
rcl_get_zero_initialized_arguments(void);
// Parse command line arguments into a structure usable by code.

/*
 \sa rcl_get_zero_initialized_arguments()

 ROS arguments are expected to be scoped by a leading `--ros-args` flag and a trailing double
 dash token `--` which may be elided if no non-ROS arguments follow after the last `--ros-args`.

 Remap rule parsing is supported via `-r/--remap` flags e.g. `--remap from:=to` or `-r from:=to`.
 Successfully parsed remap rules are stored in the order they were given in `argv`.
 If given arguments `{"__ns:=/foo", "__ns:=/bar"}` then the namespace used by nodes in this
 process will be `/foo` and not `/bar`.

 \sa rcl_remap_topic_name()
 \sa rcl_remap_service_name()
 \sa rcl_remap_node_name()
 \sa rcl_remap_node_namespace()

 Parameter override rule parsing is supported via `-p/--param` flags e.g. `--param name:=value`
 or `-p name:=value`.

*/

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_ret_t
rcl_parse_arguments(
  int argc,
  const char * const * argv,
  rcl_allocator_t allocator,
  rcl_arguments_t * args_output);
// Return the number of arguments that were not ROS specific arguments.

/*
*/

RCL_ALIGNAS(8)
__attribute__((warn_unused_result))
int
rcl_arguments_get_count_unparsed(
  const rcl_arguments_t * args);

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_ret_t
rcl_arguments_get_unparsed(
  const rcl_arguments_t * args,
  rcl_allocator_t allocator,
  int ** output_unparsed_indices);

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
int
rcl_arguments_get_count_unparsed_ros(
  const rcl_arguments_t * args);

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_ret_t
rcl_arguments_get_unparsed_ros(
  const rcl_arguments_t * args,
  rcl_allocator_t allocator,
  int ** output_unparsed_ros_indices);

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
int
rcl_arguments_get_param_files_count(
  const rcl_arguments_t * args);


__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_ret_t
rcl_arguments_get_param_files(
  const rcl_arguments_t * arguments,
  rcl_allocator_t allocator,
  char *** parameter_files);

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_ret_t
rcl_arguments_get_param_overrides(
  const rcl_arguments_t * arguments,
  rcl_params_t ** parameter_overrides);

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_ret_t
rcl_remove_ros_arguments(
  const char * const * argv,
  const rcl_arguments_t * args,
  rcl_allocator_t allocator,
  int * nonros_argc,
  const char *** nonros_argv);

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_ret_t
rcl_arguments_get_log_levels(
  const rcl_arguments_t * arguments,
  rcl_log_levels_t * log_levels);

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_ret_t
rcl_arguments_copy(
  const rcl_arguments_t * args,
  rcl_arguments_t * args_out);

__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcl_ret_t
rcl_arguments_fini(
  rcl_arguments_t * args);