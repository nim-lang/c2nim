#pragma c2nim strict
#pragma c2nim header

#pragma c2nim reorderTypes

/// The maximum length a formatted number is allowed to have.
#define RCUTILS_ERROR_STATE_LINE_NUMBER_STR_MAX_LENGTH 20 /* "18446744073709551615"*/

/// The maximum number of formatting characters allowed.
#define RCUTILS_ERROR_FORMATTING_CHARACTERS 6 /* ', at ' + ':'*/

/// The maximum formatted string length.
#define RCUTILS_ERROR_MESSAGE_MAX_LENGTH 1024

/// The maximum length for user defined error message
/**
 */
#define RCUTILS_ERROR_STATE_MESSAGE_MAX_LENGTH 768

/// The calculated maximum length for the filename.
/**
 */
#define RCUTILS_ERROR_STATE_FILE_MAX_LENGTH ( RCUTILS_ERROR_MESSAGE_MAX_LENGTH - RCUTILS_ERROR_STATE_MESSAGE_MAX_LENGTH - RCUTILS_ERROR_STATE_LINE_NUMBER_STR_MAX_LENGTH - RCUTILS_ERROR_FORMATTING_CHARACTERS - 1)

/// Struct wrapping a fixed-size c string used for returning the formatted error string.
typedef struct rcutils_error_string_s
{
  /// The fixed-size C string used for returning the formatted error string.
  char str[1024];
} rcutils_error_string_t;

/// Struct which encapsulates the error state set by RCUTILS_SET_ERROR_MSG().
typedef struct rcutils_error_state_s
{
  /// User message storage, limited to RCUTILS_ERROR_STATE_MESSAGE_MAX_LENGTH characters.
  char message[768];
  /// File name, limited to what's left from RCUTILS_ERROR_STATE_MAX_SIZE characters
  /// after subtracting storage for others.
  char file[( 1024 - 768 - 20 /* "18446744073709551615"*/ - 6 /* ', at ' + ':'*/ - 1)];
  /// Line number of error.
  uint64_t line_number;
} rcutils_error_state_t;



/// Forces initialization of thread-local storage if called in a newly created thread.
/**
 * If this function is not called beforehand, then the first time the error
 */
__attribute__ ((visibility("default")))
__attribute__((warn_unused_result))
rcutils_ret_t
rcutils_initialize_error_handling_thread_local_storage(rcutils_allocator_t allocator);

/// Set the error message, as well as the file and line on which it occurred.
void
rcutils_set_error_state(const char * error_string, const char * file, size_t line_number);
