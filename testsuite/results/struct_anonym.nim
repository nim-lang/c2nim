type
  normal* {.bycopy.} = object
    a*: cint
    b*: cint

  INNER_C_UNION_4056116588* {.bycopy.} = object {.union.}
    b*: cint

  INNER_C_STRUCT_4047855084* {.bycopy.} = object
    a_union_in_the_struct*: INNER_C_UNION_4056116588
    c*: cint

  INNER_C_STRUCT_541736491* {.bycopy.} = object
    e*: cint

  INNER_C_UNION_516951975* {.bycopy.} = object {.union.}
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_541736491

  outerStruct* {.bycopy.} = object
    a_nomal_one*: normal
    a*: cint
    ano_4089162605*: INNER_C_STRUCT_4047855084
    a_union*: INNER_C_UNION_516951975

