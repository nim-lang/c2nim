type
  fftw_double* = cdouble

##  test the toString macro operator

proc main*(argc: cint; argv: ptr cstring): cint =
  var test: fftw_double = 1.234
  printf("%s %f", "hello3", test)
  someMain(8, "7890")
  return 0
