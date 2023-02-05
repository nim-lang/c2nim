const
  fooF1* = 33
  barB1* = 44

type
  foo* {.importcpp: "foo", header: "reordertypes.hpp", bycopy.} = object
    val* {.importc: "val".}: cint


type
  bar* {.importcpp: "bar", header: "reordertypes.hpp", bycopy.} = object
    val* {.importc: "val".}: cint


const
  bazZ1* = B1

type
  baz* {.importcpp: "baz", header: "reordertypes.hpp", bycopy.} = object


converter `int`*(this: foo): cint {.noSideEffect, importcpp: "foo::operator int",
                                header: "reordertypes.hpp".}
proc `+`*(this: var bar; b: cint): cint {.importcpp: "(# + #)",
                                   header: "reordertypes.hpp".}