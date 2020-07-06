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
##  list initialization, issue #163

var list_init* {.importcpp: "list_init", header: "cpp11.hpp".}: cint

type
  NonCopy* {.importcpp: "NonCopy", header: "cpp11.hpp", bycopy.} = object


proc constructNonCopy*(): NonCopy {.constructor, importcpp: "NonCopy(@)",
                                 header: "cpp11.hpp".}
proc destroyNonCopy*(this: var NonCopy) {.importcpp: "#.~NonCopy()",
                                      header: "cpp11.hpp".}