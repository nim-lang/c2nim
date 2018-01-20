struct s1 {
    int a;
#ifdef blah
    int b;
#endif
    int c;
};

struct s2 {
    int a;
#ifdef blah
    int b;
#endif
};

struct s3 {
#ifdef blah
    int b;
#endif
    int c;
};

struct s4 {
#ifdef blah
    int b;
#endif
};
