when defined(skipme1):
  const
    thisShouldNotBeSkipped* = 1
when defined(skipme) and defined(somethingelse):
  const
    thisShouldBePresent* = 1
when defined(somethingelse) and not defined(skipme1):
  const
    oneMoreConstant* = 1
type
  foo* = object
    x*: cint
    y*: cint
    z*: cint
