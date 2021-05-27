const
  N* = 123

const
  LENGTH* = N

const
  SIZE* = N

type
  test* {.bycopy.} = object
    field*: cint
    ary*: array[SIZE, cint]


##  bug #73

type
  TestEnum* = enum
    VALUE_1 = 1


const
  TEST_ENUM_VALUE_1* = VALUE_1
