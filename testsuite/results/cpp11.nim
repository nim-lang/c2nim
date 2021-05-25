type
  Event* {.importcpp: "Event", header: "cpp11.hpp", bycopy.} = object


proc constructEvent*(): Event {.constructor, importcpp: "Event(@)",
                             header: "cpp11.hpp".}
proc `<<`*(`out`: var ostream; t: Enum): var ostream {.importcpp: "(# << #)",
    header: "cpp11.hpp".}
var foo* {.importcpp: "foo", header: "cpp11.hpp".}: Event

type
  ConstexprConstructor* {.importcpp: "ConstexprConstructor", header: "cpp11.hpp",
                         bycopy.} = object ## deprecated("getCenter() was renamed to getResourceDepot()")


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
type
  VirtClass* {.importcpp: "VirtClass", header: "cpp11.hpp", bycopy.} = object


proc constructVirtClass*(): VirtClass {.constructor, importcpp: "VirtClass(@)",
                                     header: "cpp11.hpp".}
proc destroyVirtClass*(this: var VirtClass) {.importcpp: "#.~VirtClass()",
    header: "cpp11.hpp".}
proc pureFunction*(this: var VirtClass) {.importcpp: "pureFunction",
                                      header: "cpp11.hpp".}
proc implementedFunction*(this: var VirtClass) {.importcpp: "implementedFunction",
    header: "cpp11.hpp".}
proc concreteFunction*(this: var VirtClass) {.importcpp: "concreteFunction",
    header: "cpp11.hpp".}
var my_var* {.importcpp: "VarNS::my_var", header: "cpp11.hpp".}: cint
