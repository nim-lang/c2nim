type
  MyEnum* {.size: sizeof(cint), importcpp: "test::MyEnum",
           header: "tenumnamespace.hpp".} = enum
    E1 = 0, E2 = 2


discard "forward decl of foo"
type
  bar* {.size: sizeof(cint), importcpp: "bar", header: "tenumnamespace.hpp".} = enum
    A = 0, B = 1

