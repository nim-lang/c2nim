type
  foo* {.bycopy.} = object


proc constructfoo*(): foo {.constructor.}
proc destroyfoo*(this: var foo)
proc m*(this: foo): cint {.noSideEffect.}
proc bar*(): cint