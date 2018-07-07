type
  normal* {.bycopy.} = object
    a*: cint
    b*: cint

  INNER_C_UNION_86838331* {.bycopy.} = object {.union.}
    b*: cint

  INNER_C_STRUCT_78576827* {.bycopy.} = object
    a_union_in_the_struct*: INNER_C_UNION_86838331
    c*: cint

  INNER_C_STRUCT_867425530* {.bycopy.} = object
    e*: cint

  INNER_C_UNION_842641014* {.bycopy.} = object {.union.}
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_867425530

  outerStruct* {.bycopy.} = object
    a_nomal_one*: normal
    a*: cint
    ano_119884348*: INNER_C_STRUCT_78576827
    a_union*: INNER_C_UNION_842641014

