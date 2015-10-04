type
  normal* = object
    a*: cint
    b*: cint

  INNER_C_UNION_641507247863061742* = object {.union.}
    b*: cint

  INNER_C_STRUCT_597217315833739873* = object
    a_union_in_the_struct*: INNER_C_UNION_641507247863061742
    c*: cint

  INNER_C_STRUCT_11245087157361263051* = object
    e*: cint

  INNER_C_UNION_11258561936544222101* = object {.union.}
    d*: cint
    a_struct_in_the_union*: INNER_C_STRUCT_11245087157361263051

  outerStruct* = object
    a_nomal_one*: normal
    a*: cint
    ano_589383491384313271*: INNER_C_STRUCT_597217315833739873
    a_union*: INNER_C_UNION_11258561936544222101

