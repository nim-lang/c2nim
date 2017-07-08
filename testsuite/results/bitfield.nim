type
  bits* {.bycopy.} = object
    flag* {.bitsize: 1.}: cint
    opts* {.bitsize: 4.}: cint

