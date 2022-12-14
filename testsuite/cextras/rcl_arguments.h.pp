
// Copyright 2018 Open Source Robotics Foundation, Inc.
// START

// @file
 struct rcl_arguments_impl_s rcl_arguments_impl_t;

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
__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
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
__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
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
 27 "/Users/jaremycreechley/projs/nims/ros//rcl/rcl_yaml_param_parser/include/rcl_yaml_param_parser/types.h"
      * values;
  /// Number of values in the array
  size_t size;
} rcl_bool_array_t;

/// Array of int64_t values
/*
 * \typedef rcl_int64_array_t
 */
typedef struct rcl_int64_array_s
{
  /// Array with int64 values
  int64_t * values;
  /// Number of values in the array
  size_t size;
} rcl_int64_array_t;

/// Array of double values
/*
 * \typedef rcl_double_array_t
 */
typedef struct rcl_double_array_s
{
  /// Array with double values
  double * values;
  /// Number of values in the array
  size_t size;
} rcl_double_array_t;

/// Array of byte values
/*
 * \typedef rcl_byte_array_t
 */
typedef struct rcl_byte_array_s
{
  /// Array with uint8_t values
  uint8_t * values;
  /// Number of values in the array
  size_t size;
} rcl_byte_array_t;

/// variant_t stores the value of a parameter
/*
 * Only one pointer in this struct will store the value
 * \typedef rcl_variant_t
 */
typedef struct rcl_variant_s
{
  
# 75 "/Users/jaremycreechley/projs/nims/ros//rcl/rcl_yaml_param_parser/include/rcl_yaml_param_parser/types.h" 3 4
 _Bool 
# 75 "/Users/jaremycreechley/projs/nims/ros//rcl/rcl_yaml_param_parser/include/rcl_yaml_param_parser/types.h"
      * bool_value; ///< If bool, gets      * bool_value; ///< If bool, gets stored here
  int64_t * integer_value; ///< If integer, gets stored here
  double * double_value; ///< If double, gets stored here
  char * string_value; ///< If string, gets stored here
  rcl_byte_array_t * byte_array_value; ///< If array of bytes
  rcl_bool_array_t * bool_array_value; ///< If array of bool's
  rcl_int64_array_t * integer_array_value; ///< If array of integers
  rcl_double_array_t * double_array_value; ///< If array of doubles
  rcutils_string_array_t * string_array_value; ///< If array of strings
} rcl_variant_t;

/// node_params_t stores all the parameters(key:value) of a single node
/*
* \typedef rcl_node_params_t
*/
typedef struct rcl_node_params_s
{
  char ** parameter_names; ///< Array of parameter names (keys)
  rcl_variant_t * parameter_values; ///< Array of coressponding parameter values
  size_t num_params; ///< Number of parameters in the node
  size_t capacity_params; ///< Capacity of parameters in the node
} rcl_node_params_t;

/// stores all the parameters of all nodes of a process
/*
* \typedef rcl_params_t
*/
typedef struct rcl_params_s
{
  char ** node_names; ///< List of names of the node
  rcl_node_params_t * params; ///<  Array of parameters
  size_t num_nodes; ///< Number of nodes
  size_t capacity_nodes; ///< Capacity of nodes
  rcutils_allocator_t allocator; ///< Allocator used
} rcl_params_t;
# 15 "/Users/jaremycreechley/projs/nims/c2nim/testsuite/cextras/rcl_arguments.h" 2






typedef struct rcl_arguments_impl_s rcl_arguments_impl_t;
// Hold output of parsing command line arguments.
typedef struct rcl_arguments_s
{
// Private implementation pointer.
rcl_arguments_impl_t * impl;
} rcl_arguments_t;
// The command-line flag that delineates the start of ROS arguments.
