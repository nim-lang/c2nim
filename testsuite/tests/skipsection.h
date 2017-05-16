#skipifdef skipme
#skipifndef skipme1
#skipifdef skipme2

#def skipme2 somethingelse

#ifdef skipme
#ifdef innerifdef
#define foo bar
#else
#define foo baz
#endif
#endif

#ifndef skipme1
#define thisShouldAlsoBeSkipped 1
#endif

#ifdef skipme1
#define thisShouldNotBeSkipped 1
#endif

#ifdef skipme2
#define thisShouldBeSkipped 1
#endif

#if defined(skipme)
#define thisShouldAlsoBeSkipped 1
#endif

#if defined(__cplusplus)
#define skipMeAsWell 1
#endif

struct foo {
    int x,y,z;
};