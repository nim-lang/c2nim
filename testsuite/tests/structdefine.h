#define N 123

struct test {
#define LENGTH N
  int field;
#define SIZE N
  int ary[SIZE];
};

// bug #73
enum TestEnum {
  VALUE_1 = 1,
  #define TEST_ENUM_VALUE_1 VALUE_1
};
