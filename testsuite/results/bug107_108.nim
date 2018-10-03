type
  Foo* {.bycopy.}[I: static[cint]; B: static[bool]] = object


proc `method`*[I: static[cint]; B: static[bool]](this: var Foo[I, B]; i: cint)