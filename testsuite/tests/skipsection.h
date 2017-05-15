#skip skipme

#ifdef skipme
#ifdef innerifdef
#define foo bar
#else
#define foo baz
#endif
#endif

struct foo {
    int x,y,z;
};