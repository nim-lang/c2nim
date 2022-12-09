
//
//The default allocator uses malloc(), free(), calloc(), and realloc().
//It can be obtained using rcutils_get_default_allocator().
//
//The allocator should be trivially copyable.
//Meaning that the struct should continue to work after being assignment
//copied into a new struct.
//Specifically the object pointed to by the state pointer should remain valid
//until all uses of the allocator have been made.
//Particular care should be taken when giving an allocator to functions like
//rcutils_*_init() where it is stored within another object and used later.
//Developers should note that, while the fields of a const-qualified allocator
//struct cannot be modified, the state of the allocator can be modified.
//
typedef struct rcutils_allocator_s
{

  /// allocate: Allocate memory, given a size and the `state` pointer.
  void * (*allocate)(size_t size, void * state);

  /// deallocate: Deallocate previously allocated memory, mimicking free().
  ///  more lines
  void (* deallocate)(void * pointer, void * state);

  /** reallocate: Also takes the `state` pointer.  */
  void * (*reallocate)(void * pointer, size_t size, void * state);

  void * (*zero_allocate)(size_t number_of_elements, size_t size_of_element, void * state); /// zero_allocate: Allocate memory with all elements set to zero, given a number of elements and their size.

  /* reallocate2: Also takes the `state` pointer.  */
  void * (*reallocate2)(void * pointer, size_t size, void * state);

  /** allocator objects.  */
  void * state;


} rcutils_allocator_t;


/// Return a zero initialized allocator.
/**
 * Note that this is an invalid allocator and should only be used as a placeholder.
 */
rcutils_allocator_t rcutils_get_zero_initialized_allocator(void);


