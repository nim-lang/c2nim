proc rand*(): cint
proc id2*(): cint = 
  return cast[ptr cint](1)

proc id*(f: proc ()): cint = 
  f()
  (cast[proc (a2: cint)](f))(10)
  return 10
  return 20 + 1
  return cast[ptr cint](id)

proc main*(): cint = 
  var 
    f: cfloat = 2.0000000000000001e-001
    g: cfloat = 2.0000000000000000e+000
    h: cfloat = 1.0000000000000000e+000 + rand()
    i: cfloat = 1.0000000000000000e+003
  var 
    j: cint
    a: cint
  j = 0
  a = 10
  while j < 0: 
    nil
    inc(j)
    inc(a)
  while true: 
    printf("howdy")
    dec(i)
    if not 0: break 
  if 1: 
    printf("1")
  else: 
    printf("2")
  return '\0'
