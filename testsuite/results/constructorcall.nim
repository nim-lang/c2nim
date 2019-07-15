discard "forward decl of fooBar"
type
  foo* {.bycopy.} = object
    val*: cint


proc constructfoo*(i: cint): foo {.constructor.}
proc bar*(f: foo = constructfoo(0)): cint =
  discard

proc bar*(f: fooBar = constructfooBar(0)): cint
type
  ConsInitList* {.bycopy.} = object of foo


proc constructConsInitList*(i: cint): ConsInitList {.constructor.}