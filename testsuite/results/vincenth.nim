type
  foo* {.bycopy.} = object
    x*: cint
    y*: cint
    z*: cint


##  C11 init syntax:

let lookup*: array[2, foo] = [0: (x: 1, y: 3, z: 4), 1: (x: 2, y: 3, z: 4)]
