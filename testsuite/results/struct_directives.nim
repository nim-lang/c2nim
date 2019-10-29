type
  test* {.bycopy.} = object
    when defined(A):
      var a*: cint
    when defined(B):
      var b*: cint

