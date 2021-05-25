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