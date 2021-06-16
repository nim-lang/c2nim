type
  bits* {.importcpp: "bits", header: "bitfieldwithheader.hpp", bycopy.} = object
    flag* {.importc: "flag", bitsize: 1.}: cint
    opts* {.importc: "opts", bitsize: 4.}: cint

