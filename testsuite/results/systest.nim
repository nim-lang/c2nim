##  This file has been written by Blablub.
##
##  Another comment line.
##

##  bug #127

template interrupts*(): untyped =
  sei()

const                         ##  8bit, color or not
  CV_LOAD_IMAGE_UNCHANGED* = -1 ##  8bit, gray
  CV_LOAD_IMAGE_GRAYSCALE* = 0  ##  ?, color
  CV_LOAD_IMAGE_COLOR* = 1      ##  any depth, ?
  CV_LOAD_IMAGE_ANYDEPTH* = 2   ##  ?, any color
  CV_LOAD_IMAGE_ANYCOLOR* = 4

type
  callback_t* = proc (rc: cint)
  callback2* = proc (rc: cint; L: clong; buffer: cstring): cstring

proc aw_callback_set*(c: AW_CALLBACK; callback: callback_t): cint
proc aw_instance_callback_set*(c: AW_CALLBACK; callback: callback_t): cint
var wawa*: culong

##  bug #110

type
  uint16* = cu__int16

template MAX*(x, y: untyped): untyped =
  (if (x) < (y): (y) else: (x))

const
  AW_BUILD* = 85
  AW_MAX_AVCHANGE_PER_SECOND* = 10

when not defined(expatDll):
  when defined(windows):
    const
      expatDll = "expat.dll"
  elif defined(macosx):
    const
      expatDll = "libexpat.dynlib"
  else:
    const
      expatDll = "libexpat.so(.1|)"
var uiVar*: cint

var myPrivateVar__: cint

discard "forward decl of XML_ParserStruct"
type
  ElementDeclHandler* = proc (userData: pointer; name: ptr Char; model: ptr Content) {.
      cdecl.}

var x*: pointer

proc fn*(): pointer
var fn*: proc ()

var fn*: proc (): pointer

var fn*: proc (a1: pointer): pointer

##
##  Very ugly real world code ahead:
##

type
  cjpeg_source_ptr* = ptr cjpeg_source_struct
  cjpeg_source_struct* {.bycopy.} = object
    start_input*: proc (cinfo: j_compress_ptr; sinfo: cjpeg_source_ptr)
    get_pixel_rows*: proc (cinfo: j_compress_ptr; sinfo: cjpeg_source_ptr): JDIMENSION
    finish_input*: proc (cinfo: j_compress_ptr; sinfo: cjpeg_source_ptr)
    input_file*: ptr FILE
    buffer*: JSAMPARRAY
    buffer_height*: JDIMENSION


##  bug #148

type
  jpeg_decompress_struct* {.bycopy.} = object
    coef_bits*: ptr array[64, cint]


##  Test standalone structs:

type
  myunion* {.bycopy, union.} = object
    x*: char
    y*: char
    z*: cstring
    a*: myint
    b*: myint


var u*: myunion

type
  mystruct* {.bycopy.} = object
    x*: char
    y*: char
    z*: cstring
    a*: myint
    b*: myint


proc fn*(x: i32; y: i64): mystruct
type
  mystruct* {.bycopy.} = object
    x*: char
    y*: char
    z*: cstring
    a*: myint
    b*: myint


var
  myvar*: ptr mystruct = nil
  myvar2*: ptr ptr mystruct = nil

##  anonymous struct:

var
  varX*: tuple[x: char, y: char, z: cstring, a: myint, b: myint]
  varY*: ptr ptr tuple[x: char, y: char, z: cstring, a: myint, b: myint]

##  empty anonymous struct:

var
  varX*: tuple[]
  varY*: ptr ptr tuple[]

##  Test C2NIM skipping:

template MASK*(x: untyped): untyped =
  ((x) and 0xff)

template CAST1*(x: untyped): untyped =
  ((int) and x)

template CAST2*(x: untyped): untyped =
  cast[ptr typ](addr(x))

template CAST3*(x: untyped): untyped =
  (cast[ptr ptr cuchar](addr(x)))

type
  gchar* = char
  gunsignedint* = cint
  guchar* = cuchar

var these*: cint

proc newPoint*(): ptr point =
  var i: cint = 0
  while i < 89:
    echo("test string concatenation")
    inc(i)
  while j < 54:
    discard
    inc(j)
  while true:
    ## ignored statement
    dec(j)
  while true:
    discard
  var x: ptr mytype = y * z
  if p[][] == ' ':
    dec(p)
  elif p[][] == '\t':
    inc(p, 3)
  else:
    p = 45 + cast[ptr mytype](45)
    p = 45 + (cast[ptr mytype](45))
    p = 45 + (cast[mytype](45))
    ##  BUG: This does not parse:
    ##  p = 45 + (mytype)45;
  while x >= 6 and x <= 20:
    dec(x)
  case p[]
  of 'A'..'Z', 'a'..'z':
    inc(p)
  of '0':
    inc(p)
  else:
    return nil

const
  a1* = 0
  a2* = 4
  a3* = 5

type
  myEnum* = enum
    x1, x2, x3 = 8, x4, x5
  pMyEnum* = ptr myEnum
  myEnum* = enum
    x1, x2, x3 = 8, x4, x5
  pMyEnum* = ptr myEnum



##  Test multi-line macro:

const
  MUILTILINE* = "abcxyzdef"

template MULTILINE*(x, y: untyped): void =
  while true:
    inc(y)
    inc(x)
    if not 0:
      break

when defined(windows):
  const
    iupdll* = "iup.dll"
elif defined(macosx):
  const
    iupdll* = "libiup.dynlib"
else:
  const
    iupdll* = "libiup.so"
type
  TGtkMyStruct* {.bycopy.} = object
    a*: mytype
    b*: mytype

  PGtkMyStruct* = ptr TGtkMyStruct
  TGtkMyStruct* {.bycopy.} = object
    a*: mytype
    b*: mytype

  PGtkMyStruct* = ptr TGtkMyStruct

proc IupConvertXYToPos*(ih: PIhandle; x: cint; y: cint): cint {.cdecl,
    importc: "IupConvertXYToPos", dynlib: iupdll.}
when defined(DEBUG):
  template OUT*(x: untyped): untyped =
    printf("%s\n", x)

else:
  discard
##  parses now!

proc f*(): cint {.cdecl, importc: "f", dynlib: iupdll.}
proc g*(): cint {.cdecl, importc: "g", dynlib: iupdll.}
##  does parse now!

proc f*(): cint {.cdecl, importc: "f", dynlib: iupdll.}
proc g*(): cint {.cdecl, importc: "g", dynlib: iupdll.}
var x* {.importc: "x", dynlib: iupdll.}: ptr cint

const
  abc* = 34
  xyz* = 42
  wuseldusel* = "my string\nconstant"

var x* {.importc: "x", dynlib: iupdll.}: cstring

type
  point* {.bycopy.} = object
    x*: char
    y*: char
    z*: cstring


proc printf*(frmt: cstring; ptrToStrArray: ptr cstringArray; dummy: ptr cint): cstring {.
    stdcall, varargs, cdecl, importc: "printf", dynlib: iupdll.}
proc myinlineProc*(frmt: cstring; strArray: cstringArray; dummy: ptr cint): cstring {.
    inline, varargs, cdecl, importc: "myinlineProc", dynlib: iupdll.}
##  Test void parameter list:

proc myVoidProc*() {.cdecl, importc: "myVoidProc", dynlib: iupdll.}
proc emptyReturn*() {.cdecl.} =
  return

##  POSIX stuff:

var c2nimBranch* {.importc: "c2nimBranch", dynlib: iupdll.}: cint

when defined(Windows):
  var WindowsTrue* {.importc: "WindowsTrue", dynlib: iupdll.}: cint
proc spawn*(a1: ptr pid_t; a2: cstring; a3: ptr spawn_file_actions_t;
           a4: ptr spawnattr_t; a5: ptr cstring; a6: ptr cstring): cint {.cdecl,
    importc: "posix_spawn", dynlib: iupdll.}
proc spawn_file_actions_addclose*(a1: ptr spawn_file_actions_t; a2: cint): cint {.
    cdecl, importc: "posix_spawn_file_actions_addclose", dynlib: iupdll.}
proc spawn_file_actions_adddup2*(a1: ptr spawn_file_actions_t; a2: cint; a3: cint): cint {.
    cdecl, importc: "posix_spawn_file_actions_adddup2", dynlib: iupdll.}
proc spawn_file_actions_addopen*(a1: ptr spawn_file_actions_t; a2: cint; a3: cstring;
                                a4: cint; a5: mode_t): cint {.cdecl,
    importc: "posix_spawn_file_actions_addopen", dynlib: iupdll.}
proc spawn_file_actions_destroy*(a1: ptr spawn_file_actions_t): cint {.cdecl,
    importc: "posix_spawn_file_actions_destroy", dynlib: iupdll.}
proc spawn_file_actions_init*(a1: ptr spawn_file_actions_t): cint {.cdecl,
    importc: "posix_spawn_file_actions_init", dynlib: iupdll.}
proc spawnattr_destroy*(a1: ptr spawnattr_t): cint {.cdecl,
    importc: "posix_spawnattr_destroy", dynlib: iupdll.}
proc spawnattr_getsigdefault*(a1: ptr spawnattr_t; a2: ptr sigset_t): cint {.cdecl,
    importc: "posix_spawnattr_getsigdefault", dynlib: iupdll.}
proc spawnattr_getflags*(a1: ptr spawnattr_t; a2: ptr cshort): cint {.cdecl,
    importc: "posix_spawnattr_getflags", dynlib: iupdll.}
proc spawnattr_getpgroup*(a1: ptr spawnattr_t; a2: ptr pid_t): cint {.cdecl,
    importc: "posix_spawnattr_getpgroup", dynlib: iupdll.}
proc spawnattr_getschedparam*(a1: ptr spawnattr_t; a2: ptr sched_param): cint {.cdecl,
    importc: "posix_spawnattr_getschedparam", dynlib: iupdll.}
proc spawnattr_getschedpolicy*(a1: ptr spawnattr_t; a2: ptr cint): cint {.cdecl,
    importc: "posix_spawnattr_getschedpolicy", dynlib: iupdll.}
proc spawnattr_getsigmask*(a1: ptr spawnattr_t; a2: ptr sigset_t): cint {.cdecl,
    importc: "posix_spawnattr_getsigmask", dynlib: iupdll.}
proc spawnattr_init*(a1: ptr spawnattr_t): cint {.cdecl,
    importc: "posix_spawnattr_init", dynlib: iupdll.}
proc spawnattr_setsigdefault*(a1: ptr spawnattr_t; a2: ptr sigset_t): cint {.cdecl,
    importc: "posix_spawnattr_setsigdefault", dynlib: iupdll.}
proc spawnattr_setflags*(a1: ptr spawnattr_t; a2: cshort): cint {.cdecl,
    importc: "posix_spawnattr_setflags", dynlib: iupdll.}
proc spawnattr_setpgroup*(a1: ptr spawnattr_t; a2: pid_t): cint {.cdecl,
    importc: "posix_spawnattr_setpgroup", dynlib: iupdll.}
proc spawnattr_setschedparam*(a1: ptr spawnattr_t; a2: ptr sched_param): cint {.cdecl,
    importc: "posix_spawnattr_setschedparam", dynlib: iupdll.}
proc spawnattr_setschedpolicy*(a1: ptr spawnattr_t; a2: cint): cint {.cdecl,
    importc: "posix_spawnattr_setschedpolicy", dynlib: iupdll.}
proc spawnattr_setsigmask*(a1: ptr spawnattr_t; a2: ptr sigset_t): cint {.cdecl,
    importc: "posix_spawnattr_setsigmask", dynlib: iupdll.}
proc spawnp*(a1: ptr pid_t; a2: cstring; a3: ptr spawn_file_actions_t;
            a4: ptr spawnattr_t; a5: ptr cstring; a6: ptr cstring): cint {.cdecl,
    importc: "posix_spawnp", dynlib: iupdll.}
type
  RGBType* {.bycopy.} = object
    R*: cfloat
    G*: cfloat
    B*: cfloat

  HWBType* {.bycopy.} = object
    H*: cfloat
    W*: cfloat
    B*: cfloat


proc RGB_to_HWB*(RGB: RGBType; HWB: ptr HWBType): ptr HWBType {.cdecl.} =
  var myArray: array[20, ptr HWBType]
  ##
  ##  RGB are each on [0, 1]. W and B are returned on [0, 1] and H is
  ##  returned on [0, 6]. Exception: H is returned UNDEFINED if W == 1 - B.
  ##
  var
    R: cfloat
    G: cfloat
    B: cfloat
    w: cfloat
    v: cfloat
    b: cfloat
    f: cfloat
  var i: cint
  w = MIN3(R, G, B)
  v = MAX3(R, G, B)
  b = b and 1 - v
  if v == w:
    RETURN_HWB(HWB_UNDEFINED, w, b)
  f = if (R == w): G - B else: (if (G == w): B - R else: R - G)
  i = if (R == w): 3 else: (if (G == w): 5 else: 1)
  RETURN_HWB(i - f div (v - w), w, b)

proc clip_1d*(x0: ptr cint; y0: ptr cint; x1: ptr cint; y1: ptr cint; mindim: cint;
             maxdim: cint): cint {.cdecl.} =
  var m: cdouble
  ##  gradient of line
  if x0[] < mindim:
    ##  start of line is left of window
    if x1[] < mindim:
      return 0
    m = (y1[] - y0[]) div (double)(x1[] - x0[])
    ##  calculate the slope of the line
    ##  adjust x0 to be on the left boundary (ie to be zero), and y0 to match
    dec(y0[], m * (x0[] - mindim))
    x0[] = mindim
    ##  now, perhaps, adjust the far end of the line as well
    if x1[] > maxdim:
      inc(y1[], m * (maxdim - x1[]))
      x1[] = maxdim
    return 1
  if x0[] > maxdim:
    ##  start of line is right of window - complement of above
    if x1[] > maxdim:
      return 0
    m = (y1[] - y0[]) div (double)(x1[] - x0[])
    ##  calculate the slope of the line
    inc(y0[], m * (maxdim - x0[]))
    ##  adjust so point is on the right
    ##  boundary
    x0[] = maxdim
    ##  now, perhaps, adjust the end of the line
    if x1[] < mindim:
      dec(y1[], m * (x1[] - mindim))
      x1[] = mindim
    return 1
  if x1[] > maxdim:
    ##  other end is outside to the right
    m = (y1[] - y0[]) div (double)(x1[] - x0[])
    ##  calculate the slope of the line
    inc(y1[], m * (maxdim - x1[]))
    x1[] = maxdim
    return 1
  if x1[] < mindim:
    ##  other end is outside to the left
    m = (y1[] - y0[]) div (double)(x1[] - x0[])
    ##  calculate the slope of line
    dec(y1[], m * (x1[] - mindim))
    x1[] = mindim
    return 1
  return 1

##  end of line clipping code

proc gdImageBrushApply*(im: gdImagePtr; x: cint; y: cint) {.cdecl.} =
  var
    lx: cint
    ly: cint
  var hy: cint
  var hx: cint
  var
    x1: cint
    y1: cint
    x2: cint
    y2: cint
  var
    srcx: cint
    srcy: cint
  if not im.brush:
    return
  hy = gdImageSY(im.brush) div 2
  y1 = y - hy
  y2 = y1 + gdImageSY(im.brush)
  hx = gdImageSX(im.brush) div 2
  x1 = x - hx
  x2 = x1 + gdImageSX(im.brush)
  srcy = 0
  if im.trueColor:
    if im.brush.trueColor:
      ly = y1
      while (ly < y2):
        srcx = 0
        lx = x1
        while (lx < x2):
          var p: cint
          p = gdImageGetTrueColorPixel(im.brush, srcx, srcy)
          ##  2.0.9, Thomas Winzig: apply simple full transparency
          if p != gdImageGetTransparent(im.brush):
            gdImageSetPixel(im, lx, ly, p)
          inc(srcx)
          inc(lx)
        inc(srcy)
        inc(ly)
    else:
      ##  2.0.12: Brush palette, image truecolor (thanks to Thorben Kundinger
      ##  for pointing out the issue)
      ly = y1
      while (ly < y2):
        srcx = 0
        lx = x1
        while (lx < x2):
          var
            p: cint
            tc: cint
          p = gdImageGetPixel(im.brush, srcx, srcy)
          tc = gdImageGetTrueColorPixel(im.brush, srcx, srcy)
          ##  2.0.9, Thomas Winzig: apply simple full transparency
          if p != gdImageGetTransparent(im.brush):
            gdImageSetPixel(im, lx, ly, tc)
          inc(srcx)
          inc(lx)
        inc(srcy)
        inc(ly)
  else:
    ly = y1
    while (ly < y2):
      srcx = 0
      lx = x1
      while (lx < x2):
        var p: cint
        p = gdImageGetPixel(im.brush, srcx, srcy)
        ##  Allow for non-square brushes!
        if p != gdImageGetTransparent(im.brush):
          ##  Truecolor brush. Very slow
          ##  on a palette destination.
          if im.brush.trueColor:
            gdImageSetPixel(im, lx, ly, gdImageColorResolveAlpha(im,
                gdTrueColorGetRed(p), gdTrueColorGetGreen(p),
                gdTrueColorGetBlue(p), gdTrueColorGetAlpha(p)))
          else:
            gdImageSetPixel(im, lx, ly, im.brushColorMap[p])
        inc(srcx)
        inc(lx)
      inc(srcy)
      inc(ly)

proc gdImageSetPixel*(im: gdImagePtr; x: cint; y: cint; color: cint) {.cdecl.} =
  var p: cint
  case color
  of gdStyled:
    if not im.style:
      ##  Refuse to draw if no style is set.
      return
    else:
      p = im.style[inc(im.stylePos)]
    if p != (gdTransparent):
      gdImageSetPixel(im, x, y, p)
    im.stylePos = im.stylePos mod im.styleLength
  of gdStyledBrushed:
    if not im.style:
      ##  Refuse to draw if no style is set.
      return
    p = im.style[inc(im.stylePos)]
    if (p != gdTransparent) and (p != 0):
      gdImageSetPixel(im, x, y, gdBrushed)
    im.stylePos = im.stylePos mod im.styleLength
  of gdBrushed:
    gdImageBrushApply(im, x, y)
  of gdTiled:
    gdImageTileApply(im, x, y)
  of gdAntiAliased: ##  This shouldn't happen (2.0.26) because we just call
                  ##  gdImageAALine now, but do something sane.
    gdImageSetPixel(im, x, y, im.AA_color)
  else:
    if gdImageBoundsSafeMacro(im, x, y):
      if im.trueColor:
        if im.alphaBlendingFlag:
          im.tpixels[y][x] = gdAlphaBlend(im.tpixels[y][x], color)
        else:
          im.tpixels[y][x] = color
      else:
        im.pixels[y][x] = color
