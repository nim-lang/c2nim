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

#pure wxEdge
enum wxEdge
{
    wxLeft, wxTop, wxRight, wxBottom, wxWidth, wxHeight,
    wxCentre, wxCenter = wxCentre, wxCentreX, wxCentreY
};

// bug #136

static inline void bcf_float_set(float *ptr, uint32_t value)
{
    union { uint32_t i; float f; } u;
    u.i = value;
    *ptr = u.f;
}

#isarray a

void sort(int* a, int len);

// bug #32

int x(){
#if fii
    if(1) {
    }
#else
    return 1;
#endif
}


#define someU64 12333ull

#define someU32 12333ul
#define someI64 12333LL
#define someI32 12333l
