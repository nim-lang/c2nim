#pragma c2nim clibUserPragma

//
//The default allocator uses malloc(), free(), calloc(), and realloc().
typedef struct rcutils_allocator_s
{

  /// allocate: Allocate memory, given a size and the `state` pointer.
  void * (*allocate)(size_t size, void * state);

  /** allocator objects.  */
  void * state;


} rcutils_allocator_t;


/// Return a zero initialized allocator.
/**
 * Note that this is an invalid allocator and should only be used as a placeholder.
 */
rcutils_allocator_t rcutils_get_zero_initialized_allocator(void);


