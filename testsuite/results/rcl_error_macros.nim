const
  RCUTILS_ERROR_STATE_LINE_NUMBER_STR_MAX_LENGTH* = 20 ##
                              ##  The maximum length a formatted number is allowed to have.
  RCUTILS_ERROR_FORMATTING_CHARACTERS* = 6 ##  The maximum number of formatting characters allowed.
  RCUTILS_ERROR_MESSAGE_MAX_LENGTH* = 1024 ##  The maximum formatted string length.
  RCUTILS_ERROR_STATE_MESSAGE_MAX_LENGTH* = 768 ##  The maximum length for user defined error message
                                                ##
                                                ##

type

  rcutils_error_string_t* {.importc: "rcutils_error_string_t",
                            header: "rcl_error_macros.h", bycopy.} = object ##
                              ##  Struct wrapping a fixed-size c string used for returning the formatted error string.
    str* {.importc: "str".}: array[1024, char] ##  The fixed-size C string used for returning the formatted error string.


  rcutils_error_state_t* {.importc: "rcutils_error_state_t",
                           header: "rcl_error_macros.h", bycopy.} = object ##
                              ##  Struct which encapsulates the error state set by RCUTILS_SET_ERROR_MSG().
    message* {.importc: "message".}: array[768, char] ##
                              ##  User message storage, limited to RCUTILS_ERROR_STATE_MESSAGE_MAX_LENGTH characters.
    file* {.importc: "file".}: array[(1024 - 768 - 20 - 6 - 1), char] ##
                              ##  File name, limited to what's left from RCUTILS_ERROR_STATE_MAX_SIZE characters
                              ##  after subtracting storage for others.
    line_number* {.importc: "line_number".}: uint64 ##
                              ##  Line number of error.


const
  RCUTILS_ERROR_STATE_FILE_MAX_LENGTH* = (RCUTILS_ERROR_MESSAGE_MAX_LENGTH -
      RCUTILS_ERROR_STATE_MESSAGE_MAX_LENGTH -
      RCUTILS_ERROR_STATE_LINE_NUMBER_STR_MAX_LENGTH -
      RCUTILS_ERROR_FORMATTING_CHARACTERS -
      1)                     ##  The calculated maximum length for the filename.
                             ##
                             ##


proc rcutils_initialize_error_handling_thread_local_storage*(
    allocator: rcutils_allocator_t): rcutils_ret_t {.
    importc: "rcutils_initialize_error_handling_thread_local_storage",
    header: "rcl_error_macros.h".}
  ##  Forces initialization of thread-local storage if called in a newly created thread.
                                  ##
                                  ##  If this function is not called beforehand, then the first time the error
                                  ##

proc rcutils_set_error_state*(error_string: cstring; file: cstring;
                              line_number: csize_t) {.
    importc: "rcutils_set_error_state", header: "rcl_error_macros.h".}
  ##
                              ##  Set the error message, as well as the file and line on which it occurred.