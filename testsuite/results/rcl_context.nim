##  Copyright 2018 Open Source Robotics Foundation, Inc.
##
##  Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
##  You may obtain a copy of the License at
##
##      http://www.apache.org/licenses/LICENSE-2.0
##
##  Unless required by applicable law or agreed to in writing, software
##  distributed under the License is distributed on an "AS IS" BASIS,
##  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##  See the License for the specific language governing permissions and
##  limitations under the License.
##  @file

import
  rmw/init, rcl/allocator, rcl/arguments, rcl/init_options, rcl/macros, rcl/types,
  rcl/visibility_control

type
  rcl_context_instance_id_t* = uint64 ##  A unique ID per context instance.
  rcl_context_impl_t* = rcl_context_impl_s

type
  rcl_context_t* {.importc: "rcl_context_t", header: "rcl_context.h", bycopy.} = object ##  Encapsulates the non-global state of an init/shutdown cycle.
                                                                                ##
                                                                                ##  The context is used in the creation of top level entities like nodes and
                                                                                ##  guard conditions, as well as to shutdown a specific instance of init.
                                                                                ##
                                                                                ##  Here is a diagram of a typical context's lifecycle:
                                                                                ##
                                                                                ##  ```
                                                                                ##     +---------------+
                                                                                ##     |               |
                                                                                ##  +--> uninitialized +---> rcl_get_zero_initialized_context() +
                                                                                ##  |  |               |                                        |
                                                                                ##  |  +---------------+                                        |
                                                                                ##  |                                                           |
                                                                                ##  |           +-----------------------------------------------+
                                                                                ##  |           |
                                                                                ##  |  +--------v---------+                +-----------------------+
                                                                                ##  |  |                  |                |                       |
                                                                                ##  |  | zero-initialized +-> rcl_init() +-> initialized and valid +-> rcl_shutdown() +
                                                                                ##  |  |                  |                |                       |                  |
                                                                                ##  |  +------------------+                +-----------------------+                  |
                                                                                ##  |                                                                                 |
                                                                                ##  |               +-----------------------------------------------------------------+
                                                                                ##  |               |
                                                                                ##  |  +------------v------------+
                                                                                ##  |  |                         |
                                                                                ##  |  | initialized but invalid +---> finalize all entities, then rcl_context_fini() +
                                                                                ##  |  |                         |                                                    |
                                                                                ##  |  +-------------------------+                                                    |
                                                                                ##  |                                                                                 |
                                                                                ##  +---------------------------------------------------------------------------------+
                                                                                ##  ```
                                                                                ##
                                                                                ##  A declared but not defined rcl_context_t instance is considered to be
                                                                                ##  "uninitialized", and passing an uninitialized context to any functions will
                                                                                ##  result in undefined behavior.
                                                                                ##  Some functions, like rcl_init() require the context instance to be
                                                                                ##  zero initialized (all members set to "zero" state) before use.
                                                                                ##
                                                                                ##  Zero initialization of an rcl_context_t should be done with
                                                                                ##  rcl_get_zero_initialized_context(), which ensures the context is in a safe
                                                                                ##  state for initialization with rcl_init().
                                                                                ##
                                                                                ##  Initialization of an rcl_context_t should be done with rcl_init(), after
                                                                                ##  which the context is considered both initialized and valid.
                                                                                ##  After initialization it can be used in the creation of other entities like
                                                                                ##  nodes and guard conditions.
                                                                                ##
                                                                                ##  At any time the context can be invalidated by calling rcl_shutdown() on
                                                                                ##  the rcl_context_t, after which the context is still initialized but now
                                                                                ##  invalid.
                                                                                ##
                                                                                ##  Invalidation indicates to other entities that the context was shutdown, but
                                                                                ##  is still accessible for use during cleanup of themselves.
                                                                                ##
                                                                                ##  After being invalidated, and after all of the entities which used it have
                                                                                ##  been finalized, the context should be finalized with rcl_context_fini().
                                                                                ##
                                                                                ##  Finalizing the context while entities which have copies of it have not yet
                                                                                ##  been finalized is undefined behavior.
                                                                                ##  Therefore, the context's lifetime (between calls to rcl_init() and
                                                                                ##  rcl_context_fini()) should exceed the lifetime of all entities which use
                                                                                ##  it directly (e.g. nodes and guard conditions) or indirectly (e.g.
                                                                                ##  subscriptions and topics).
                                                                                ##
    global_arguments* {.importc: "global_arguments".}: rcl_arguments_t ##  Global arguments for all nodes which share this context.
                                                                   ##  Typically generated by the parsing of argc/argv in rcl_init().
    impl* {.importc: "impl".}: ptr rcl_context_impl_t ##  Implementation specific pointer.
    ##  The assumption that this is big enough for an atomic_uint_least64_t is
    ##  ensured with a static_assert in the context.c file.
    ##  In most cases it should just be a plain uint64_t.
    ##  @cond Doxygen_Suppress
    when not defined(RCL_CONTEXT_ATOMIC_INSTANCE_ID_STORAGE_SIZE):
      const
        RCL_CONTEXT_ATOMIC_INSTANCE_ID_STORAGE_SIZE* = sizeof((uint_least64_t))
    ##  @endcond
    ##  Private storage for instance ID atomic.
    instance_id_storage* {.importc: "instance_id_storage".}: array[
        RCL_CONTEXT_ATOMIC_INSTANCE_ID_STORAGE_SIZE, uint8] ##
                                                          ##  Accessing the instance id should be done using the function
                                                          ##
                                                          ## rcl_context_get_instance_id() because the instance id's type is an
                                                          ##  atomic and needs to be accessed properly to ensure safety.
                                                          ##
                                                          ##  The instance id should not be changed manually - doing so is undefined
                                                          ##  behavior.
                                                          ##
                                                          ##  The instance id cannot be protected within the `impl` pointer's type
                                                          ##  because it needs to be accessible even when the context is zero
                                                          ##  initialized and therefore `impl` is `NULL`.
                                                          ##  Specifically, storing the instance id in the `impl` would introduce a
                                                          ##  race condition between accessing it and finalizing the context.
                                                          ##  Additionally, C11 atomics (i.e. "stdatomic.h") cannot be used directly
                                                          ##  here in the case that this header is included into a C++ program.
                                                          ##  See this paper for an effort to make this possible in the future:
                                                          ##
                                                          ## http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2018/p0943r1.html
                                                          ##



proc rcl_get_zero_initialized_context*(): rcl_context_t {.
    importc: "rcl_get_zero_initialized_context", header: "rcl_context.h".}
  ##  Return a zero initialization context object.

proc rcl_context_fini*(context: ptr rcl_context_t): rcl_ret_t {.
    importc: "rcl_context_fini", header: "rcl_context.h".}
  ##  Finalize a context.
  ##
  ##  The context to be finalized must have been previously initialized with
  ##  rcl_init(), and then later invalidated with rcl_shutdown().
  ##  A zero-initialized context that has not been initialized can be finalized.
  ##  If context is `NULL`, then #RCL_RET_INVALID_ARGUMENT is returned.
  ##  If context is zero-initialized, then #RCL_RET_OK is returned.
  ##  If context is initialized and valid (rcl_shutdown() was not called on it),
  ##  then #RCL_RET_INVALID_ARGUMENT is returned.
  ##
  ##  <hr>
  ##  Attribute          | Adherence
  ##  ------------------ | -------------
  ##  Allocates Memory   | Yes
  ##  Thread-Safe        | No
  ##  Uses Atomics       | Yes
  ##  Lock-Free          | Yes [1]
  ##  <i>[1] if `atomic_is_lock_free()` returns true for `atomic_uint_least64_t`</i>
  ##
  ##  \param[inout] context object to be finalized.
  ##  \return #RCL_RET_OK if the shutdown was completed successfully, or
  ##  \return #RCL_RET_INVALID_ARGUMENT if any arguments are invalid, or
  ##  \return #RCL_RET_ERROR if an unspecified error occur.
  ##

proc rcl_context_get_init_options*(context: ptr rcl_context_t): ptr rcl_init_options_t {.
    importc: "rcl_context_get_init_options", header: "rcl_context.h".}
  ##  Return the init options used during initialization for this context.
  ##
  ##  This function can fail and return `NULL` if:
  ##    - context is NULL
  ##    - context is zero-initialized, e.g. context->impl is `NULL`
  ##
  ##  If context is uninitialized then that is undefined behavior.
  ##
  ##  If `NULL` is returned an error message will have been set.
  ##
  ##  The options are for reference only, and therefore the returned pointer is
  ##  const.
  ##  Changing the values in the options is undefined behavior but will likely
  ##  have no effect.
  ##
  ##  <hr>
  ##  Attribute          | Adherence
  ##  ------------------ | -------------
  ##  Allocates Memory   | No
  ##  Thread-Safe        | Yes
  ##  Uses Atomics       | Yes
  ##  Lock-Free          | Yes
  ##
  ##  \param[in] context object from which the init options should be retrieved
  ##  \return pointer to the the init options, or
  ##  \return `NULL` if there was an error
  ##

proc rcl_context_get_instance_id*(context: ptr rcl_context_t): rcl_context_instance_id_t {.
    importc: "rcl_context_get_instance_id", header: "rcl_context.h".}
  ##  Returns an unsigned integer that is unique to the given context, or `0` if invalid.
  ##
  ##  The given context must be non-`NULL`, but does not need to be initialized or valid.
  ##  If context is `NULL`, then `0` will be returned.
  ##  If context is uninitialized, then it is undefined behavior.
  ##
  ##  The instance ID may be `0` if the context is zero-initialized or if the
  ##  context has been invalidated by rcl_shutdown().
  ##
  ##  <hr>
  ##  Attribute          | Adherence
  ##  ------------------ | -------------
  ##  Allocates Memory   | No
  ##  Thread-Safe        | Yes
  ##  Uses Atomics       | Yes
  ##  Lock-Free          | Yes [1]
  ##  <i>[1] if `atomic_is_lock_free()` returns true for `atomic_uint_least64_t`</i>
  ##
  ##  \param[in] context object from which the instance id should be retrieved
  ##  \return a unique id specific to this context instance, or
  ##  \return `0` if invalid, or
  ##  \return `0` if context is `NULL`
  ##

proc rcl_context_get_domain_id*(context: ptr rcl_context_t; domain_id: ptr csize_t): rcl_ret_t {.
    importc: "rcl_context_get_domain_id", header: "rcl_context.h".}
  ##  Returns the context domain id.
  ##
  ##  \pre If context is uninitialized, then it is undefined behavior.
  ##
  ##  <hr>
  ##  Attribute          | Adherence
  ##  ------------------ | -------------
  ##  Allocates Memory   | No
  ##  Thread-Safe        | Yes [1]
  ##  Uses Atomics       | No
  ##  Lock-Free          | No
  ##
  ##  <i>[1] Calling the function asynchronously with rcl_init() or rcl_shutdown() can result
  ##   in the function sometimes succeeding and sometimes returning #RCL_RET_INVALID_ARGUMENT.</i>
  ##
  ##  \param[in] context from which the domain id should be retrieved.
  ##  \param[out] domain_id output variable where the domain id will be returned.
  ##  \return #RCL_RET_INVALID_ARGUMENT if `context` is invalid (see rcl_context_is_valid()), or
  ##  \return #RCL_RET_INVALID_ARGUMENT if `domain_id` is `NULL`, or
  ##  \return #RCL_RET_OK if the domain id was correctly retrieved.
  ##

proc rcl_context_is_valid*(context: ptr rcl_context_t): bool {.
    importc: "rcl_context_is_valid", header: "rcl_context.h".}
  ##  Return `true` if the given context is currently valid, otherwise `false`.
  ##
  ##  If context is `NULL`, then `false` is returned.
  ##  If context is zero-initialized, then `false` is returned.
  ##  If context is uninitialized, then it is undefined behavior.
  ##
  ##  Attribute          | Adherence
  ##  ------------------ | -------------
  ##  Allocates Memory   | No
  ##  Thread-Safe        | Yes
  ##  Uses Atomics       | Yes
  ##  Lock-Free          | Yes [1]
  ##  <i>[1] if `atomic_is_lock_free()` returns true for `atomic_uint_least64_t`</i>
  ##
  ##  \param[in] context object which should be checked for validity
  ##  \return `true` if valid, otherwise `false`
  ##

proc rcl_context_get_rmw_context*(context: ptr rcl_context_t): ptr rmw_context_t {.
    importc: "rcl_context_get_rmw_context", header: "rcl_context.h".}
  ##  Return pointer to the rmw context if the given context is currently valid, otherwise `NULL`.
  ##
  ##  If context is `NULL`, then `NULL` is returned.
  ##  If context is zero-initialized, then `NULL` is returned.
  ##  If context is uninitialized, then it is undefined behavior.
  ##
  ##  Attribute          | Adherence
  ##  ------------------ | -------------
  ##  Allocates Memory   | No
  ##  Thread-Safe        | Yes
  ##  Uses Atomics       | Yes
  ##  Lock-Free          | Yes [1]
  ##  <i>[1] if `atomic_is_lock_free()` returns true for `atomic_uint_least64_t`</i>
  ##
  ##  \param[in] context object from which the rmw context should be retrieved.
  ##  \return pointer to rmw context if valid, otherwise `NULL`
  ## 