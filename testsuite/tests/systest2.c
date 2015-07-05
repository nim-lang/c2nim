#ifdef C2NIM
#  header "iup.h"
#  cdecl
#  mangle "'GTK_'{.*}" "TGtk$1"
#  mangle "'PGTK_'{.*}" "PGtk$1"
#endif

typedef struct stupidTAG {
  mytype a, b;
} GTK_MyStruct, *PGTK_MyStruct;

typedef struct  {
  mytype a, b;
} GTK_MyStruct, *PGTK_MyStruct;

int IupConvertXYToPos(PIhandle ih, int x, int y);

#def FOO_0()
#def FOO_1
#def FOO_2(x) x

FOO_0()
FOO_2(FOO_1)
FOO_1

#ifdef C2NIM
#@
proc handwrittenNim(): string =
  "@#"

@#
#endif

#define foobar #@ 5 or 9
@#
