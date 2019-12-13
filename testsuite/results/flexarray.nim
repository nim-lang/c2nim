type
  aaa_t* {.bycopy.} = object
    c*: cint
    a*: UncheckedArray[cint]

  bbb_t* {.bycopy.} = object
    c*: cint
    a*: UncheckedArray[cint]

