const
  MYIGNORE* = true
  MYCDECL* = __cdecl

proc test1*(): cint =
  var x: cint = 1
  return x

proc test2*(): cint {.cdecl.} =
  var x: cint = 2
  return x

when defined(MYIGNORE):
  var myVar*: cint
  proc test3*(): cint =
    myVar = test1()
    myVar = myVar + test2()
    return myVar
