type
  Foo*[I: static[cint]; B: static[bool]] {.bycopy.} = object


proc `method`*[I: static[cint]; B: static[bool]](this: var Foo[I, B]; i: cint)