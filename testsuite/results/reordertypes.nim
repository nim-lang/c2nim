const
  fooF1* = 33

const
  barB1* = 44

type
  foo* {.importcpp: "foo", header: "reordertypes.hpp", bycopy.} = object
    val* {.importc: "val".}: cint


type
  bar* {.importcpp: "bar", header: "reordertypes.hpp", bycopy.} = object
    val* {.importc: "val".}: cint


converter `int`*(this: foo): cint {.noSideEffect, importcpp: "foo::operator int",
                                header: "reordertypes.hpp".}
proc `+`*(this: var bar; b: cint): cint {.importcpp: "(# + #)",
                                   header: "reordertypes.hpp".}