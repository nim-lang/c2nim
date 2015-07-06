type 
  TGtkMyStruct* {.importc: "GTK_MyStruct", header: "iup.h".} = object 
    a* {.importc: "a".}: mytype
    b* {.importc: "b".}: mytype

  PGtkMyStruct* = ptr TGtkMyStruct
  TGtkMyStruct* {.importc: "GTK_MyStruct", header: "iup.h".} = object 
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
    wxLeft, wxTop, wxRight, wxBottom, wxWidth, wxHeight, wxCentre, 
    wxCenter = wxCentre, wxCentreX, wxCentreY

