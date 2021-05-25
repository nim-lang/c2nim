type
  Double* {.bycopy.} = object
    bits*: bits_type           ##  = p   (includes the hidden bit)
                   ##  = 2^(p-1)
                   ##  = 2^(p-1) - 1

  value_type* = cdouble
  bits_type* = uint64_t

const
  SignificandSize*: int32_t = digits

const
  ExponentBias*: int32_t = max_exponent - 1 + (SignificandSize - 1)

const
  MaxIeeeExponent*: bits_type = bits_type(2 * max_exponent - 1)

const
  HiddenBit*: bits_type = bits_type(1) shl (SignificandSize - 1)

const
  SignificandMask*: bits_type = HiddenBit - 1

const
  ExponentMask*: bits_type = MaxIeeeExponent shl (SignificandSize - 1)

const
  SignMask*: bits_type = not (not bits_type(0) shr 1)

proc constructDouble*(bits_: bits_type): Double {.constructor.} =
  discard

proc constructDouble*(value: value_type): Double {.constructor.} =
  discard

proc main*(): cint =
  var foo: vector[int64_t] = vector[int64_t](10)
  return 0

proc test1*(): cint =
  var x: cint = 1
  return x

proc test2*(): cint {.cdecl.} =
  var x: cint = 2
  return x

var myVar*: cint

proc test3*(): cint =
  myVar = test1()
  myVar = myVar + test2()
  return myVar

proc test4*(): cint =
  myVar = test1()
  myVar = myVar + test2()
  return myVar

when defined(DEBUG):
  template OUT*(x: untyped): untyped =
    printf("%s\n", x)

else:
  discard
##  bug #190

type
  QObjectData* {.bycopy.} = object
    q_ptr*: ptr QObject
    parent*: ptr QObject
    children*: QObjectList
    isWidget* {.bitsize: 1.}: uint
    blockSig* {.bitsize: 1.}: uint
    wasDeleted* {.bitsize: 1.}: uint
    isDeletingChildren* {.bitsize: 1.}: uint
    sendChildEvents* {.bitsize: 1.}: uint
    receiveChildEvents* {.bitsize: 1.}: uint
    isWindow* {.bitsize: 1.}: uint ##  for QWindow
    deleteLaterCalled* {.bitsize: 1.}: uint
    unused* {.bitsize: 24.}: uint
    postedEvents*: cint
    metaObject*: ptr QDynamicMetaObjectData
    bindingStorage*: QBindingStorage


proc constructQObjectData*(): QObjectData {.constructor.}
proc destroyQObjectData*(this: var QObjectData)
proc dynamicMetaObject*(this: QObjectData): ptr QMetaObject {.noSideEffect.}
##  C++ lambdas

var ex1*: auto = (proc (x: cint): auto =
  cout shl x shl '\n')

var ex2*: auto = (proc (): auto =
  code)

var ex3*: auto = (proc (f: cfloat; a: cint): auto =
  return a * f)

var ex4*: auto = (proc (t: MyClass): cint =
  var a: auto = t.compute()
  return a)

var ex5*: auto = (proc (a: cint; b: cint): auto =
  return a < b)

var myLambda*: auto = (proc (a: cint): cdouble =
  return 2.0 * a)

var myLambda*: auto = (proc (a: cint): auto =
  cout shl a)

var baz*: auto = (proc (): auto =
  var x: cint = 10
  if x < 20:
    return x * 1.1
  else:
    return x * 2.1
  )

var
  x*: cint = 1
  y*: cint = 1

(proc (): auto =
  inc(x)
  inc(y))()
##  <-- call ()

proc main*(): cint =
  var x: cint = 10
  var y: cint = 11
  ##  Captures With an Initializer
  var foo: auto = (proc (): auto =
    cout shl z shl '\n')
  foo()
  var p: unique_ptr[cint] = unique_ptr[cint](new(int(10)))
  var foo: auto = (proc (): auto =
    inc(x))
  var bar: auto = (proc (): auto = discard )
  var baz: auto = (proc (): auto = discard )

##  decltype

var i*: cint

var j*: typeof(i + 3)

type
  Foo* = function[proc ()]
