type
  bits* = object
    flag*: cint
    {.bitsize:1.}
    opts*: cint
    {.bitsize:4.}

