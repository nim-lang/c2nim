#define MYIGNORE
#define MYCDECL   __cdecl

int test1() { int x = 1; return (x); }
MYCDECL int test2() { int x = 2; return (x); }

#ifdef MYIGNORE
  int myVar;

  MYIGNORE int test3() {
        myVar = test1();
	myVar = myVar + test2();
	return(myVar);
  }

#endif 
