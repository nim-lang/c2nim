type
  normal* {.bycopy.} = object
    a*: cint
    b*: cint

  INNER_C_STRUCT_struct_anonym_as_fields_3* {.bycopy.} = object
    e*: cint

  outerStruct* {.bycopy.} = object
    a_nomal_one*: normal
    a*: cint
    anon1_b*: cint
    anon1_ab*: cfloat
    c*: cint
    anon2_d*: cint
    anon2_a_struct_in_the_union*: INNER_C_STRUCT_struct_anonym_as_fields_3

