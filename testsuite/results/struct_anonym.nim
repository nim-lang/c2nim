type 
  normal* = object 
    a*: cint
    b*: cint

  INNER_C_UNION_2814606598* = object  {.union.}
    b*: cint

  INNER_C_STRUCT_3682850820* = object 
    a_union_in_the_struct*: INNER_C_UNION_2814606598
    c*: cint

  INNER_C_STRUCT_2821978930* = object 
    e*: cint

  INNER_C_UNION_3201809032* = object  {.union.}
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_2821978930

  outerStruct* = object 
    a_nomal_one*: normal
    a*: cint
    ano_388512601*: INNER_C_STRUCT_3682850820
    a_union*: INNER_C_UNION_3201809032

