type
  INNER_C_STRUCT_nestedanonymousstruct_3* {.bycopy.} = object
    a*: cint

  INNER_C_STRUCT_nestedanonymousstruct_2* {.bycopy.} = object
    meow*: INNER_C_STRUCT_nestedanonymousstruct_3

  miauz* {.bycopy.} = object
    meow2*: INNER_C_STRUCT_nestedanonymousstruct_2

