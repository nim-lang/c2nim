#nep1
#reordercomments
#mergeblocks
#delete RmwErrorStringT
#delete RmwErrorStateT



/// Struct wrapping a fixed-size c string used for returning the formatted error string.
typedef rcutils_error_string_t rmw_error_string_t;

/// Struct which encapsulates the error state set by RMW_SET_ERROR_MSG().
typedef rcutils_error_state_t rmw_error_state_t;

