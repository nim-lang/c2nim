nil
discard "forward decl of vector"
type
  Foo* {.importcpp: "Foo<\'0>", header: "nested.hpp", bycopy.}[T] = object
    someArray* {.importc: "someArray".}: array[FooMAX_DIM, cint]

  FooInt* = cint
  FooBaseType*[T] = T
  FooBaseTypePtr*[T] = ptr T
  FooBasTypeArray*[T] = array[3, T]
  FooVector*[T] = vector[T]
  FooIterator*[T] = vectoriterator[T]

proc constructFoo*[T](): Foo[T] {.constructor, importcpp: "Foo<\'*0>(@)",
                               header: "nested.hpp".}
type
  FooDeepEnum* {.size: sizeof(cint).} = enum
    ENUM1, ENUM2


const
  FooMIN_DIM* = 5
  FooMAX_DIM* = 10

proc methodeNestedStruct*[T](this: var FooNestedStruct[T]) {.
    importcpp: "methodeNestedStruct", header: "nested.hpp".}
type
  FooNestedClassVeryDeepEnum* {.size: sizeof(cint).} = enum
    ENUM3, ENUM4


proc methodeNestedClass*[T](this: var FooNestedClass[T]) {.
    importcpp: "methodeNestedClass", header: "nested.hpp".}
type
  FooNestedStruct* {.importcpp: "Foo<\'0>::NestedStruct", header: "nested.hpp",
                    bycopy.}[T] = object
    i* {.importc: "i".}: cint
    j* {.importc: "j".}: cint

  FooNestedClass* {.importcpp: "Foo<\'0>::NestedClass", header: "nested.hpp", bycopy.}[
      T] = object
    i* {.importc: "i".}: cint
    j* {.importc: "j".}: cint

  FooOtherNestedClass* {.importcpp: "Foo<\'0>::OtherNestedClass<\'1,\'2>",
                        header: "nested.hpp", bycopy.}[T; T1; T2] = object
    val1* {.importc: "val1".}: T1
    val2* {.importc: "val2".}: T2 ##  The following constructors and destructors cannot be translated
                              ##  for now (both child and parent are generic)
                              ## OtherNestedClass(); 
                              ## OtherNestedClass(int i);
                              ## ~OtherNestedClass();
  
  FooOtherNestedClassVeryDeepEnum* {.size: sizeof(cint).} = enum
    ENUM5, ENUM6


proc methodeNestedClass*[T; T1; T2](this: var FooOtherNestedClass[T, T1, T2]) {.
    importcpp: "methodeNestedClass", header: "nested.hpp".}
type
  Bar* {.importcpp: "Bar<\'0,\'1>", header: "nested.hpp", bycopy.}[T; I: static[cint]] = object
  
  BarMyStruct*[T] = FooNestedStruct[T]
  BarNestedClass* {.importcpp: "Bar<\'0,\'1>::NestedClass", header: "nested.hpp",
                   bycopy.}[T; I: static[cint]] = object
    val* {.importc: "val".}: cint

  BarNestedClass2* {.importcpp: "Bar<\'0,\'1>::NestedClass2<\'2>",
                    header: "nested.hpp", bycopy.}[T; I: static[cint]; T1] = object
    val* {.importc: "val".}: T1  ## NestedClass2();
  
  NoTemplate* {.importcpp: "NoTemplate", header: "nested.hpp", bycopy.} = object
  
  NoTemplateDeepEnum* {.size: sizeof(cint), importcpp: "NoTemplate::DeepEnum",
                       header: "nested.hpp".} = enum
    ENUM7, ENUM8


type
  NoTemplateNestedClass2* {.importcpp: "NoTemplate::NestedClass2",
                           header: "nested.hpp", bycopy.} = object
    val* {.importc: "val".}: cint


proc constructNoTemplateNestedClass2*(): NoTemplateNestedClass2 {.constructor,
    importcpp: "NoTemplate::NestedClass2(@)", header: "nested.hpp".}
proc constructNoTemplateNestedClass2*(i: cint): NoTemplateNestedClass2 {.
    constructor, importcpp: "NoTemplate::NestedClass2(@)", header: "nested.hpp".}