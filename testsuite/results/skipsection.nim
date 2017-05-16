when defined(skipme1):
  const
    thisShouldNotBeSkipped* = 1
type
  foo* = object
    x*: cint
    y*: cint
    z*: cint
