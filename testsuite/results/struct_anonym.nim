type 
  normal* = object 
    a*: cint
    b*: cint

  INNER_C_UNION_4161638671* = object  {.union.}
    b*: cint

  INNER_C_STRUCT_3680257704* = object 
    a_union_in_the_struct*: INNER_C_UNION_4161638671
    c*: cint

  INNER_C_STRUCT_3403983474* = object 
    e*: cint

  INNER_C_UNION_1138184789* = object  {.union.}
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_3403983474

  outerStruct* = object 
    a_nomal_one*: normal
    a*: cint
    ano_388512601*: INNER_C_STRUCT_3680257704
    a_union*: INNER_C_UNION_1138184789

