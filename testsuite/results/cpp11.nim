type
  Event* {.importcpp: "Event", header: "cpp11.hpp", bycopy.} = object


proc constructEvent*(): Event {.constructor, importcpp: "Event(@)",
                             header: "cpp11.hpp".}
proc `<<`*(`out`: var ostream; t: Enum): var ostream {.importcpp: "(# << #)",
    header: "cpp11.hpp".}
var foo* {.importcpp: "foo", header: "cpp11.hpp".}: Event

type
  ConstexprConstructor* {.importcpp: "ConstexprConstructor", header: "cpp11.hpp",
                         bycopy.} = object


proc constructConstexprConstructor*(i: cint = 1): ConstexprConstructor {.constructor,
    importcpp: "ConstexprConstructor(@)", header: "cpp11.hpp".}