##  posix signal

var proc (a1: cint; a2: proc (a1: cint)): signal*: proc (a1: cint)
# proc signal*(a1: cint; a2: proc (a1: cint)): proc (a1: cint)

##  str signal

proc strsignal*(__sig: cint): cstring
##  str signal

proc strsignal_r*(__sig: cint; __strsignalbuf: cstring; __buflen: csize_t): cint
##  attributes

var _close*: proc (a1: pointer): cint

var _read*: proc (a1: pointer; a2: cstring; a3: cint): cint

##  __attribute__

proc vasprintf*(a1: cstringArray; a2: cstring; a3: __gnuc_va_list): cint
proc __assert_rtn*(a1: cstring; a2: cstring; a3: cint; a4: cstring)
proc malloc*(__size: csize_t): pointer
##  struct attribute

type
  _OSUnalignedU16* {.bycopy.} = object
    __val*: uint16_t

