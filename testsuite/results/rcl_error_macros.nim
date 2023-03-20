##  #pragma c2nim reorderTypes
##  The maximum length a formatted number is allowed to have.

const
  RCUTILS_ERROR_STATE_LINE_NUMBER_STR_MAX_LENGTH* = 20

##  The maximum number of formatting characters allowed.

const
  RCUTILS_ERROR_FORMATTING_CHARACTERS* = 6

##  The maximum formatted string length.

const
  RCUTILS_ERROR_MESSAGE_MAX_LENGTH* = 1024

##  The maximum length for user defined error message
##
##

const
  RCUTILS_ERROR_STATE_MESSAGE_MAX_LENGTH* = 768

##  The calculated maximum length for the filename.
##
##

const
  RCUTILS_ERROR_STATE_FILE_MAX_LENGTH* = (RCUTILS_ERROR_MESSAGE_MAX_LENGTH -
      RCUTILS_ERROR_STATE_MESSAGE_MAX_LENGTH -
      RCUTILS_ERROR_STATE_LINE_NUMBER_STR_MAX_LENGTH -
      RCUTILS_ERROR_FORMATTING_CHARACTERS -
      1)

##  Struct wrapping a fixed-size c string used for returning the formatted error string.

type
  rcutils_error_string_t* {.importc: "rcutils_error_string_t",
                            header: "rcl_error_macros.h", bycopy.} = object
    ##  The fixed-size C string used for returning the formatted error string.
    str* {.importc: "str".}: array[1024, char]


##  Struct which encapsulates the error state set by RCUTILS_SET_ERROR_MSG().

type
  rcutils_error_state_t* {.importc: "rcutils_error_state_t",
                           header: "rcl_error_macros.h", bycopy.} = object
    ##  User message storage, limited to RCUTILS_ERROR_STATE_MESSAGE_MAX_LENGTH characters.
    message* {.importc: "message".}: array[768, char]
    ##  File name, limited to what's left from RCUTILS_ERROR_STATE_MAX_SIZE characters
    ##  after subtracting storage for others.
    file* {.importc: "file".}: array[(1024 - 768 - 20 - 6 - 1), char]
    ##  Line number of error.
    line_number* {.importc: "line_number".}: uint64


##  Forces initialization of thread-local storage if called in a newly created thread.
##
##  If this function is not called beforehand, then the first time the error
##

proc rcutils_initialize_error_handling_thread_local_storage*(
    allocator: rcutils_allocator_t): rcutils_ret_t {.
    importc: "rcutils_initialize_error_handling_thread_local_storage",
    header: "rcl_error_macros.h".}
##  Set the error message, as well as the file and line on which it occurred.

proc rcutils_set_error_state*(error_string: cstring; file: cstring;
                              line_number: csize_t) {.
    importc: "rcutils_set_error_state", header: "rcl_error_macros.h".}