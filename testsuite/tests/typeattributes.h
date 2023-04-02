__declspec(align(16)) struct S1Align{
   int a;
};

__declspec(deprecated) struct S1Deprecated{
   int a;
};

struct __attribute__((aligned(16))) S2Align {
    int a;
};

struct __attribute__((deprecated)) S2Deprecated {
    int a;
};


struct S3Packed {
    int a;
} __attribute__((packed));

struct S3Align {
    int a;
} __attribute__((aligned(16)));

struct S3Deprecated {
    int a;
} __attribute__((deprecated));

struct S3Packed {
    int a;
} __attribute__((packed));

typedef int deprecated_int __attribute__ ((deprecated));

struct __attribute__((deprecated, packed, aligned(16))) MultiplyAttributes {
  int a;
};

struct __declspec(deprecated, packed, aligned(16)) MultiplyAttributesDeclspec {
  int a;
};

typedef struct __attribute__((packed, aligned(8)))
{
     int a;
} S4;

typedef struct __declspec(align(8))
{
     int a;
} S4decl;


__attribute__((aligned(128))) struct A {
    int i;
} S5;

typedef struct
{
     int a;
} __attribute__((packed, aligned(8))) S6;


typedef struct
{
     int a;
} __declspec(packed, aligned(8)) S6decl;

#if defined(__GNUC__) || defined(__clang__)
#  define ALIGN(x) __attribute__ ((aligned(x)))
#elif defined(_MSC_VER)
#  define ALIGN(x) __declspec(align(x))
#else
#  error "Unknown compiler; can't define ALIGN"
#endif

struct ALIGN(32) MyStruct
{
    int a;
};
