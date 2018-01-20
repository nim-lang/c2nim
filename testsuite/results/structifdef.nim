type
  s1* {.bycopy.} = object
    a*: cint
    when defined(blah):
      var b*: cint
    c*: cint

  s2* {.bycopy.} = object
    a*: cint
    when defined(blah):
      var b*: cint

  s3* {.bycopy.} = object
    when defined(blah):
      var b*: cint
    c*: cint

  s4* {.bycopy.} = object
    when defined(blah):
      var b*: cint

