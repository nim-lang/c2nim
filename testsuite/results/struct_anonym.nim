type
  normal* {.bycopy.} = object
    a*: cint
    b*: cint

  INNER_C_UNION_191243455* {.bycopy.} = object {.union.}
    b*: cint

  INNER_C_STRUCT_182981951* {.bycopy.} = object
    a_union_in_the_struct*: INNER_C_UNION_191243455
    c*: cint

  INNER_C_STRUCT_971830654* {.bycopy.} = object
    e*: cint

  INNER_C_UNION_947046138* {.bycopy.} = object {.union.}
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_971830654

  outerStruct* {.bycopy.} = object
    a_nomal_one*: normal
    a*: cint
    ano_224289472*: INNER_C_STRUCT_182981951
    a_union*: INNER_C_UNION_947046138

