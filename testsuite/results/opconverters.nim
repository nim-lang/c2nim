type
  foo* {.importcpp: "foo", header: "opconverters.hpp", bycopy.} = object
    val* {.importc: "val".}: cint


converter `int`*(this: foo): cint {.noSideEffect, importcpp: "foo::operator int",
                                header: "opconverters.hpp".}