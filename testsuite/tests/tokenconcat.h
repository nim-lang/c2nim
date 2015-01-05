#ifndef C2NIM
# define CAT(x,y) x ## y
# define MANGLE_DOUBLE(x,y) typedef y CAT(x,y)
#else
# def CAT(x,y) x ## y
# def MANGLE_DOUBLE(x,y) typedef y CAT(x,y)
#endif
 
 
MANGLE_DOUBLE(fftw_, double);

// test the toString macro operator

#def toString(x) #x

int main(int argc, char *argv[])
{
  fftw_double test = 1.234;
  printf("%s %f","hello3", test);
  someMain(8, toString(7890));

  return 0;
}
