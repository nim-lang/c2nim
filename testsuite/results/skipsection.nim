const
  thisShouldNotBeSkipped* = 1

when defined(skipme) or defined(somethingelse):
  const
    thisShouldBePresent* = 1
when not defined(skipme1) or defined(somethingelse):
  const
    oneMoreConstant* = 1
type
  foo* {.bycopy.} = object
    x*: cint
    y*: cint
    z*: cint

