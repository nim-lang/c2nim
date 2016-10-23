type
  normal* = object
    a*: cint
    b*: cint

  INNER_C_UNION_3731612527* = object {.union.}
    b*: cint

  INNER_C_STRUCT_3723351023* = object
    a_union_in_the_struct*: INNER_C_UNION_3731612527
    c*: cint

  INNER_C_STRUCT_217232430* = object
    e*: cint

  INNER_C_UNION_192447914* = object {.union.}
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_217232430

  outerStruct* = object
    a_nomal_one*: normal
    a*: cint
    ano_3764658544*: INNER_C_STRUCT_3723351023
    a_union*: INNER_C_UNION_192447914

