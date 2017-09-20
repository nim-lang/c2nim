discard "forward decl of fooBar"
type
  foo* {.bycopy.} = object
    val*: cint


proc constructfoo*(i: cint): foo {.constructor.}
proc bar*(f: foo = constructfoo(0)): cint
proc bar*(f: fooBar = constructfooBar(0)): cint