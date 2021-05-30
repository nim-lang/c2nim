type
  TGtkMyStruct* {.importc: "GTK_MyStruct", header: "iup.h", bycopy.} = object
    a* {.importc: "a".}: mytype
    b* {.importc: "b".}: mytype

  PGtkMyStruct* = ptr TGtkMyStruct
  TGtkMyStruct* {.importc: "GTK_MyStruct", header: "iup.h", bycopy.} = object
    a* {.importc: "a".}: mytype
    b* {.importc: "b".}: mytype

  PGtkMyStruct* = ptr TGtkMyStruct

proc IupConvertXYToPos*(ih: PIhandle; x: cint; y: cint): cint {.cdecl,
    importc: "IupConvertXYToPos", header: "iup.h".}
proc handwrittenNim(): string =
  "@#"

const
  foobar* = 5 or 9

type
  wxEdge* {.size: sizeof(cint), pure.} = enum
    wxLeft, wxTop, wxRight, wxBottom, wxWidth, wxHeight, wxCentre, wxCentreX, wxCentreY

const
  wxCenter* = wxCentre

##  bug #136

proc bcf_float_set*(`ptr`: ptr cfloat; value: uint32_t) {.inline, cdecl.} =
  type
    INNER_C_UNION_systest2_48 {.importc: "no_name", header: "iup.h", bycopy, union.} = object
      i: uint32_t
      f: cfloat

  var u: INNER_C_UNION_systest2_48
  u.i = value
  `ptr`[] = u.f

proc sort*(a: ptr UncheckedArray[cint]; len: cint) {.cdecl, importc: "sort",
    header: "iup.h".}
##  bug #32

proc x*(): cint {.cdecl.} =
  when fii:
    if 1:
      discard
  else:
    return 1
