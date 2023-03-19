type
  normal* {.bycopy.} = object
    a*: cint
    b*: cint

  INNER_C_STRUCT_struct_anonym_as_fields_3* {.bycopy.} = object
    e*: cint

  outerStruct* {.bycopy.} = object
    a_nomal_one*: normal
    a*: cint
    b*: cint
    ab*: cfloat
    c*: cint
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_struct_anonym_as_fields_3

