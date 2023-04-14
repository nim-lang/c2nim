
const rosImportDynamic {.strdefine.}: string = ""
when rosImportDynamic == "":
  {.pragma: clib, header: "rcutils/time.h" .}
else:
  {.pragma: clib, dynlib: "" & importDynamic.}

type

  rcutils_allocator_t* {.importc: "rcutils_allocator_t", clib, bycopy.} = object ##
                              ##
                              ## The default allocator uses malloc(), free(), calloc(), and realloc().
    allocate* {.importc: "allocate".}: proc (size: csize_t; state: pointer): pointer ##
                              ##  allocate: Allocate memory, given a size and the `state` pointer.
    state* {.importc: "state".}: pointer ##  allocator objects.



proc rcutils_get_zero_initialized_allocator*(): rcutils_allocator_t {.
    importc: "rcutils_get_zero_initialized_allocator", clib.}
  ##  Return a zero initialized allocator.
                                          ##
                                          ##  Note that this is an invalid allocator and should only be used as a placeholder.
                                          ## 