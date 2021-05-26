## !!!Ignored construct:  this makes no sense here ;
## Error: token expected: ; but got: [identifier]!!!

proc fn*(x: cint; y: cint) =
  cout shl "blag"

## !!!Ignored construct:  more stuff that is wrong ;
## Error: token expected: ; but got: [identifier]!!!

proc fn2*(x: cint; y: cint) =
  ## !!!Ignored construct:  same shit in function ;
  ## Error: token expected: ; but got: [identifier]!!!
  cout shl "blag"
  unknown

type
  Double* {.bycopy.} = object
    bits*: bits_type           ##  = p   (includes the hidden bit)
                   ##  = 2^(p-1)
                   ##  = 2^(p-1) - 1
    does*: this
    parse*: `not`


## !!!Ignored construct:  static_assert ( std :: numeric_limits < double > :: is_iec559 && std :: numeric_limits < double > :: digits == 53 && std :: numeric_limits < double > :: max_exponent == 1024 , IEEE-754 double-precision implementation required ) ;
## Error: token expected: ) but got: ::!!!

type
  value_type* = cdouble
  bits_type* = uint64_t

const
  SignificandSize*: int32_t = digits[value_type]

const
  ExponentBias*: int32_t = max_exponent[value_type] - 1 + (SignificandSize - 1)

const
  MaxIeeeExponent*: bits_type = bits_type(2 * max_exponent[value_type] - 1)

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

proc PhysicalSignificand*(this: Double): bits_type {.noSideEffect.} =
  return bits and SignificandMask

proc PhysicalExponent*(this: Double): bits_type {.noSideEffect.} =
  return (bits and ExponentMask) shr (SignificandSize - 1)

proc IsFinite*(this: Double): bool {.noSideEffect.} =
  return (bits and ExponentMask) != ExponentMask

proc IsInf*(this: Double): bool {.noSideEffect.} =
  return (bits and ExponentMask) == ExponentMask and
      (bits and SignificandMask) == 0

proc IsNaN*(this: Double): bool {.noSideEffect.} =
  return (bits and ExponentMask) == ExponentMask and
      (bits and SignificandMask) != 0

proc IsZero*(this: Double): bool {.noSideEffect.} =
  return (bits and not SignMask) == 0

proc SignBit*(this: Double): bool {.noSideEffect.} =
  return (bits and SignMask) != 0
