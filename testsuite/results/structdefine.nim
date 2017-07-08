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

