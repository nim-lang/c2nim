type
  Event* = object
  

proc constructEvent*(): Event {.constructor.}
proc `<<`*(`out`: var ostream; t: Enum): var ostream