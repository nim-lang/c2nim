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

