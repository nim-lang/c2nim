type
  Foo* {.importcpp: "Foo", header: "commaop.hpp", bycopy.} = object
  

proc `,`*(this: var Foo; i: cint): cint {.importcpp: "#,@", header: "commaop.hpp".}