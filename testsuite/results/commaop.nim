type
  Foo* {.importcpp: "struct Foo", header: "commaop.hpp", bycopy.} = object


proc `comma`*(this: var Foo; i: cint): cint {.importcpp: "#,@", header: "commaop.hpp".}