type
  normal* {.bycopy.} = object
    a*: cint
    b*: cint

  INNER_C_UNION_struct_anonym_14* {.bycopy.} = object {.union.}
    b*: cint

  INNER_C_STRUCT_struct_anonym_13* {.bycopy.} = object
    a_union_in_the_struct*: INNER_C_UNION_struct_anonym_14
    c*: cint

  INNER_C_STRUCT_struct_anonym_24* {.bycopy.} = object
    e*: cint

  INNER_C_UNION_struct_anonym_21* {.bycopy.} = object {.union.}
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_struct_anonym_24

  outerStruct* {.bycopy.} = object
    a_nomal_one*: normal
    a*: cint
    ano_struct_anonym_18*: INNER_C_STRUCT_struct_anonym_13
    a_union*: INNER_C_UNION_struct_anonym_21

