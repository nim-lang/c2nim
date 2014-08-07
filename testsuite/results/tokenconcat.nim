type 
  fftw_double* = cdouble

proc main*(argc: cint; argv: ptr cstring): cint = 
  var test: fftw_double = 1.234
  printf("%s %f", "hello3", test)
  return 0
