type
  rcutils_allocator_t* {.importc: "rcutils_allocator_t", header: "rcl_allocator.h",
                        bycopy.} = object ##
                                       ## The default allocator uses malloc(), free(), calloc(), and realloc().
                                       ## It can be obtained using rcutils_get_default_allocator().
                                       ##
                                       ## The allocator should be trivially copyable.
                                       ## Meaning that the struct should continue to work after being assignment
                                       ## copied into a new struct.
                                       ## Specifically the object pointed to by the state pointer should remain valid
                                       ## until all uses of the allocator have been made.
                                       ## Particular care should be taken when giving an allocator to functions like
                                       ## rcutils_*_init() where it is stored within another object and used later.
                                       ## Developers should note that, while the fields of a const-qualified allocator
                                       ## struct cannot be modified, the state of the allocator can be modified.
                                       ##
    allocate* {.importc: "allocate".}: proc (size: csize_t; state: pointer): pointer ##  allocate: Allocate memory, given a size and the `state` pointer.
    deallocate* {.importc: "deallocate".}: proc (pointer: pointer; state: pointer) ##  deallocate: Deallocate previously allocated memory, mimicking free().
                                                                           ##   more lines
    reallocate* {.importc: "reallocate".}: proc (pointer: pointer; size: csize_t;
        state: pointer): pointer ##  reallocate: Also takes the `state` pointer.
    zero_allocate* {.importc: "zero_allocate".}: proc (number_of_elements: csize_t;
        size_of_element: csize_t; state: pointer): pointer ##  zero_allocate: Allocate memory with all elements set to zero, given a number of elements and their size.
    reallocate2* {.importc: "reallocate2".}: proc (pointer: pointer; size: csize_t;
        state: pointer): pointer ##  reallocate2: Also takes the `state` pointer.
    state* {.importc: "state".}: pointer ##  allocator objects.



proc rcutils_get_zero_initialized_allocator*(): rcutils_allocator_t {.
    importc: "rcutils_get_zero_initialized_allocator", header: "rcl_allocator.h".}
  ##  Return a zero initialized allocator.
  ##
  ##  Note that this is an invalid allocator and should only be used as a placeholder.
  ## 