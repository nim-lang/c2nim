#skip skipme

#ifdef skipme
#ifdef innerifdef
#define foo bar
#else
#define foo baz
#endif
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