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