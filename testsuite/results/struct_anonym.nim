type
  normal* {.bycopy.} = object
    a*: cint
    b*: cint

  INNER_C_UNION_struct_anonym_1* {.bycopy, union.} = object
    b*: cint

  INNER_C_STRUCT_struct_anonym_0* {.bycopy.} = object
    a_union_in_the_struct*: INNER_C_UNION_struct_anonym_1
    c*: cint

  INNER_C_STRUCT_struct_anonym_4* {.bycopy.} = object
    e*: cint

  INNER_C_UNION_struct_anonym_3* {.bycopy, union.} = object
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_struct_anonym_4

  outerStruct* {.bycopy.} = object
    a_nomal_one*: normal
    a*: cint
    ano_struct_anonym_2*: INNER_C_STRUCT_struct_anonym_0
    a_union*: INNER_C_UNION_struct_anonym_3

