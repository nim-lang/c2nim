type
  failClass1* {.bycopy.} = object
    tmpI*: cint
    when 0:
      atLeastSkipThis*: cint


proc someProc*(this: var failClass1; x: cint)
type
  failClass2* {.bycopy.} = object
    tmpI*: cint
    when not defined(unknown):
      myfield*: pointer


const
  myconst* = 122

when defined(unknown):
  proc someIfdefProc*(this: var failClass2; x: cint)