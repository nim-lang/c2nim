type
  normal* {.bycopy.} = object
    a*: cint
    b*: cint

  INNER_C_UNION_3731612527* {.bycopy.} = object {.union.}
    b*: cint

  INNER_C_STRUCT_3723351023* {.bycopy.} = object
    a_union_in_the_struct*: INNER_C_UNION_3731612527
    c*: cint

  INNER_C_STRUCT_217232430* {.bycopy.} = object
    e*: cint

  INNER_C_UNION_192447914* {.bycopy.} = object {.union.}
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_217232430

  outerStruct* {.bycopy.} = object
    a_nomal_one*: normal
    a*: cint
    ano_3764658544*: INNER_C_STRUCT_3723351023
    a_union*: INNER_C_UNION_192447914

