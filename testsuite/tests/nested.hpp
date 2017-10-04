#include <vector>
#include <string>
using namespace std;

template <typename T>
class vector;

template <typename T>
class Foo {
public:
  typedef int Int;
  typedef T BaseType;
  typedef T* BaseTypePtr;
  typedef T BasTypeArray[3];
  typedef typename std::vector<T> Vector;
  typedef typename std::vector<T>::iterator Iterator;

  typedef enum {
    ENUM1, ENUM2
  } DeepEnum;

  enum {
    ENUM3, ENUM4
  };

  typedef struct {
    int i, j;
  } NestedStruct;


  typedef class irrelevantTag {
  public:
    typedef enum {
      ENUM1, ENUM2
    } VeryDeepEnum;

    int i, j;
  } NestedClass;

  template <typename T1, typename T2>
  class OtherNestedClass {
  public:
    typedef enum {
      ENUM1, ENUM2
    } VeryDeepEnum;
    T1 val1;
    T2 val2;
  };
};

template <typename T, int I>
class Bar{
public:
        typedef typename Foo<T>::NestedStruct MyStruct;

        typedef class {
        public:
                int val;

        } NestedClass;

        template<typename T1>
        class NestedClass2 {
        public:
                T1 val;
        };
};


class NoTemplate {
public:
        typedef enum {
                ENUM1, ENUM2
        } DeepEnum;
};
