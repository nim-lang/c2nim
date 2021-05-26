#include <vector>
#include <string>
using namespace std;

template <typename T>
class vector; // so that vector<T>::iterator is maped to vectoriterator[T] and not just iterator[T]

template <typename T>
class Foo {
public:
  typedef int Int;
  typedef T BaseType;
  typedef T* BaseTypePtr;
  typedef T BasTypeArray[3];
  typedef typename std::vector<T> Vector;
  typedef typename std::vector<T>::iterator Iterator;

  Foo(){};

  //~Foo(); // this cannot be translated for now as Foo is generic

  typedef enum {
    ENUM1, ENUM2
  } DeepEnum;

  enum {
    MIN_DIM=5, MAX_DIM=10
  };

  int someArray[MAX_DIM];

  typedef struct {
    void methodeNestedStruct(){};
    int i, j;
  } NestedStruct;


  typedef class irrelevantTag {
  public:
    typedef enum {
      ENUM3, ENUM4
    } VeryDeepEnum;

    void methodeNestedClass(){};

    int i, j;
  } NestedClass;

  template <typename T1, typename T2>
  class OtherNestedClass {
  public:
    typedef enum {
      ENUM5, ENUM6
    } VeryDeepEnum;
    T1 val1;
    T2 val2;

    // The following constructors and destructors cannot be translated
    // for now (both child and parent are generic)
    //OtherNestedClass(); 
    //OtherNestedClass(int i);
    //~OtherNestedClass();
    
    void methodeNestedClass(){};
  };

  //void method(NestedClass & n, NestedStruct* b, OtherNestedClass<string, string> * c); 
  // OtherNestedClass<string, string> is still translated to FooOtherNestedClass[string, string], 
  // missing T as first generic argument

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

                //NestedClass2();
        };
};


class NoTemplate {
public:
        typedef enum {
                ENUM7, ENUM8
        } DeepEnum;

        class NestedClass2 {
        public:
                int val;
                NestedClass2(){};
                NestedClass2(int i){};
        };
};
