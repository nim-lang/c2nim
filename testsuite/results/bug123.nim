const
  test*: cint = 1

type
  arr* = array[test, cint]

proc main*(): cint =
  discard
