type
  S1Align* {.bycopy.} = object
    a* {.align: 16.}: cint

  S1Deprecated* {.bycopy, deprecated.} = object
    a*: cint

  S2Align* {.bycopy.} = object
    a* {.align: 16.}: cint

  S2Deprecated* {.bycopy, deprecated.} = object
    a*: cint

  S3Packed* {.bycopy, packed.} = object
    a*: cint

  S3Align* {.bycopy.} = object
    a* {.align: 16.}: cint

  S3Deprecated* {.bycopy, deprecated.} = object
    a*: cint

  S3Packed* {.bycopy, packed.} = object
    a*: cint

  deprecated_int* {.deprecated.} = cint
  MultiplyAttributes* {.bycopy, deprecated, packed.} = object
    a* {.align: 16.}: cint

  MultiplyAttributesDeclspec* {.bycopy, deprecated, packed.} = object
    a* {.align: 16.}: cint

  S4* {.bycopy, packed.} = object
    a* {.align: 8.}: cint

  S4decl* {.bycopy.} = object
    a* {.align: 8.}: cint

  A* {.bycopy.} = object
    i* {.align: 128.}: cint


var S5*: A

type
  S6* {.bycopy, packed.} = object
    a* {.align: 8.}: cint

  S6decl* {.bycopy, packed.} = object
    a* {.align: 8.}: cint


when defined(__GNUC__) or defined(__clang__):
  discard
elif defined(_MSC_VER):
  discard
else:
  discard
type
  MyStruct* {.bycopy.} = object
    a* {.align: 32.}: cint

