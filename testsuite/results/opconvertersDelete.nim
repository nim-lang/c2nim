type
  foo* {.importcpp: "foo", header: "opconvertersDelete.hpp", bycopy.} = object
    val* {.importc: "val".}: cint

