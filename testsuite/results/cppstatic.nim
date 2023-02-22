type
  ClassA* {.importcpp: "ClassA", header: "cppstatic.hpp", bycopy.} = object


proc test*(_: `type` ClassA) {.importcpp: "ClassA::test(@)",
                               header: "cppstatic.hpp".}
type
  ClassB* {.importcpp: "ClassB", header: "cppstatic.hpp", bycopy.} = object


proc test*(_: `type` ClassB) {.importcpp: "ClassB::test(@)",
                               header: "cppstatic.hpp".}
type
  ClassGeneric*[T] {.importcpp: "ClassGeneric<\'0>", header: "cppstatic.hpp",
                     bycopy.} = object


proc test*[T](_: `type` ClassGeneric[T]) {.importcpp: "ClassGeneric::test(@)",
    header: "cppstatic.hpp".}
proc test*() {.importcpp: "test(@)", header: "cppstatic.hpp".}