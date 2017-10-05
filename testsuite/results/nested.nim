nil
discard "forward decl of vector"
type
  Foo* {.importcpp: "Foo", header: "nested.hpp", bycopy.}[T] = object
    someArray* {.importc: "someArray".}: array[FooMAX_DIM, cint]

  FooInt* = cint
  FooBaseType*[T] = T
  FooBaseTypePtr*[T] = ptr T
  FooBasTypeArray*[T] = array[3, T]
  FooVector*[T] = vector[T]
  FooIterator*[T] = vectoriterator[T]
  FooDeepEnum* {.size: sizeof(cint).} = enum
    ENUM1, ENUM2


const
  FooMIN_DIM* = 5
  FooMAX_DIM* = 10

type
  FooNestedClassVeryDeepEnum* {.size: sizeof(cint).} = enum
    ENUM1, ENUM2


type
  FooNestedStruct* {.importcpp: "Foo<\'0>::NestedStruct", header: "nested.hpp",
                    bycopy.}[T] = object
    i* {.importc: "i".}: cint
    j* {.importc: "j".}: cint

  FooNestedClass* {.importcpp: "Foo<\'0>::NestedClass", header: "nested.hpp", bycopy.}[
      T] = object
    i* {.importc: "i".}: cint
    j* {.importc: "j".}: cint

  FooOtherNestedClass* {.importcpp: "Foo<\'0>::OtherNestedClass",
                        header: "nested.hpp", bycopy.}[T; T1; T2] = object
    val1* {.importc: "val1".}: T1
    val2* {.importc: "val2".}: T2

  FooOtherNestedClassVeryDeepEnum* {.size: sizeof(cint).} = enum
    ENUM1, ENUM2


proc `method`*[T](this: var Foo[T]; n: var FooNestedClass) {.importcpp: "method",
    header: "nested.hpp".}
type
  Bar* {.importcpp: "Bar", header: "nested.hpp", bycopy.}[T; I: static[cint]] = object
  
  BarMyStruct*[T] = FooNestedStruct[T]
  BarNestedClass* {.importcpp: "Bar<\'0,\'1>::NestedClass", header: "nested.hpp",
                   bycopy.}[T; I: static[cint]] = object
    val* {.importc: "val".}: cint

  BarNestedClass2* {.importcpp: "Bar<\'0,\'1>::NestedClass2", header: "nested.hpp",
                    bycopy.}[T; I: static[cint]; T1] = object
    val* {.importc: "val".}: T1

  NoTemplate* {.importcpp: "NoTemplate", header: "nested.hpp", bycopy.} = object
  
  NoTemplateDeepEnum* {.size: sizeof(cint), importcpp: "NoTemplate::DeepEnum",
                       header: "nested.hpp".} = enum
    ENUM1, ENUM2

