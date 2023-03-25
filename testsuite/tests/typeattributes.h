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
