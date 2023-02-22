type
  Test* {.importcpp: "Test", header: "removeduplicates.hpp", bycopy.} = object


proc cvptr*(this: var Test; idx: ptr cint): cstring {.importcpp: "cvptr",
    header: "removeduplicates.hpp".}
proc cvptr*(this: Test; idx: ptr cint): cstring {.noSideEffect,
    importcpp: "cvptr", header: "removeduplicates.hpp".}