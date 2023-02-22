=======================
  c2nim User's manual
=======================

:Author: Andreas Rumpf
:Version: |c2nimversion|

.. contents::

Introduction
============

  "We all make choices. But in the end our choices make us."


c2nim is a tool to translate ANSI C/C++ code to Nim. The output is
human-readable Nim code that is meant to be tweaked by hand after the
translation process. c2nim is not a real compiler!

c2nim is preliminary meant to translate C header files. Because of this, the
preprocessor is part of the parser. For example:

.. code-block:: C

  #define abc 123
  #define xyz 789

Is translated into:

.. code-block:: Nim

  const
    abc* = 123
    xyz* = 789


c2nim is meant to translate fragments of C code and thus does not follow
include files. c2nim cannot parse all of ANSI C/C++ and many constructs cannot
be represented in Nim: for example `duff's device`:idx: cannot be translated
to Nim.

Standard Nim Style Guide
========================

You're strongly adviced to always use the `--nep1` command line switch;
with this switch enabled, c2nim generates Nim names that follow Nim's official
style guide.


Notes for developers
====================

To add support for a new C/C++ syntactic construct, it's usually a good idea
to start where the current parser fails: `c2nim --debug --strict file.cpp`
produces a useful stack trace that points at the source location that is to be
changed.


Preprocessor support
====================

Even though the translation process is not perfect, it is often the case that
the translated Nim code does not need any tweaking by hand. In other cases
it may be preferable to modify the input file instead of the generated Nim
code so that c2nim can parse it properly. c2nim's preprocessor defines the
symbol ``C2NIM`` that can be used to mark code sections:

.. code-block:: C

  #ifndef C2NIM
    // C2NIM should ignore this prototype:
    int fprintf(FILE* f, const char* frmt, ...);
  #endif

The ``C2NIM`` symbol is only recognized in ``#ifdef`` and ``#ifndef``
constructs! ``#if defined(C2NIM)`` does **not** work.

c2nim *processes* ``#ifdef C2NIM`` and ``#ifndef C2NIM`` directives, but other
``#if[def]`` directives are *translated* into Nim's ``when`` construct:

.. code-block:: C

  #ifdef DEBUG
  #  define OUT(x) printf("%s\n", x)
  #else
  #  define OUT(x)
  #endif

Is translated into:

.. code-block:: Nim

  when defined(debug):
    template OUT*(x: expr): expr =
      printf("%s\x0A", x)
  else:
    discard

As can be seen from the example, C's macros with parameters are mapped
to Nim's templates. This mapping is the best one can do, but it is of course
not accurate: Nim's templates operate on syntax trees whereas C's
macros work on the token level.

c2nim's preprocessor supports special directives that affect how the output
is generated. They should be put into a ``#ifdef C2NIM`` section so that
ordinary C compilers ignore them.


``#skipinclude`` directive
--------------------------
**Note**: There is also a ``--skipinclude`` command line option that can be
used for the same purpose.

By default, c2nim translates an ``#include`` that is not followed by ``<``
(like in ``#include <stdlib>``) to a Nim ``import`` statement. With this
directive enabled, c2nim skips any ``#include``.


``#stdcall`` and ``#cdecl`` directives
--------------------------------------
**Note**: There are also ``--stdcall`` and ``--cdecl`` command line options
that can be used for the same purpose.

These directives tell c2nim that it should annotate every proc (or proc type)
with the ``stdcall`` / ``cdecl`` calling convention.


``#dynlib`` directive
---------------------
**Note**: There is also a ``--dynlib`` command line option that can be used for
the same purpose.

This directive enables that c2nim does annotate every proc that resulted
from a C function prototype with the ``dynlib`` pragma:

.. code-block:: C

  #ifdef C2NIM
  #  dynlib iupdll
  #  cdecl
  #  if defined(windows)
  #    define iupdll "iup.dll"
  #  elif defined(macosx)
  #    define iupdll "libiup.dylib"
  #  else
  #    define iupdll "libiup.so"
  #  endif
  #endif

  int IupConvertXYToPos(PIhandle ih, int x, int y);

Is translated to:

.. code-block:: Nim

  when defined(windows):
    const iupdll* = "iup.dll"
  elif defined(macosx):
    const iupdll* = "libiup.dylib"
  else:
    const iupdll* = "libiup.so"

  proc IupConvertXYToPos*(ih: PIhandle, x: cint, y: cint): cint {.
    importc: "IupConvertXYToPos", cdecl, dynlib: iupdll.}

Note how the example contains extra C code to declare the ``iupdll`` symbol
in the generated Nim code.


``#header`` directive
---------------------
**Note**: There is also a ``--header`` command line option that can be used for
the same purpose.

The ``#header`` directive enables that c2nim annotates every proc that
resulted from a C function prototype and every exported variable and type with
the ``header`` pragma:

.. code-block:: C

  #ifdef C2NIM
  #  header "iup.h"
  #endif

  int IupConvertXYToPos(PIhandle ih, int x, int y);

Is translated to:

.. code-block:: Nim

  proc IupConvertXYToPos*(ih: PIhandle, x: cint, y: cint): cint {.
    importc: "IupConvertXYToPos", header: "iup.h".}

The ``#header`` and the ``#dynlib`` directives are mutually exclusive.
A binding that uses ``dynlib`` is much more preferable over one that uses
``header``! The Nim compiler might drop support for the ``header`` pragma
in the future as it cannot work for backends that do not generate C code.


``#prefix`` and ``#suffix`` directives
--------------------------------------

**Note**: There are also ``--prefix`` and ``--suffix`` command line options
that can be used for the same purpose.

c2nim does not do any name mangling by default. However the
``#prefix`` and ``#suffix`` directives can be used to strip prefixes and
suffixes from the identifiers in the C code:

.. code-block:: C

  #ifdef C2NIM
  #  prefix Iup
  #  dynlib dllname
  #  cdecl
  #endif

  int IupConvertXYToPos(PIhandle ih, int x, int y);

Is translated to:

.. code-block:: Nim

  proc ConvertXYToPos*(ih: PIhandle, x: cint, y: cint): cint {.
    importc: "IupConvertXYToPos", cdecl, dynlib: dllname.}


``#mangle`` directive
---------------------

Even more sophisticated name mangling can be achieved by the ``#mangle``
directive: It takes a PEG pattern and format string that specify how the
identifier should be converted:

.. code-block:: C

  #mangle "'GTK_'{.*}" "TGtk$1"

For convenience the PEG pattern and the replacement can be single identifiers
too, there is no need to quote them:

.. code-block:: C

  #mangle ssize_t  int
  // is short for:
  #mangle "'ssize_t'" "int"
  
To fix leading/trailing/underscore identifiers in C code use `#mangle "^'_'*{@}('_'*$)" "$1"`

``#assumedef`` and ``#assumendef`` directives
----------------------------------------------

**Note**: There are also ``--assumedef`` and ``--assumendef`` command line
options that can be used for the same purpose.

c2nim can be configured to skip certain ``#ifdef`` or ``#ifndef`` sections.
If a directive ``#assumedef SYMBOL``is found, c2nim will assume that the symbol
``SYMBOL`` is defined, and thus skip ``#ifndef SYMBOL`` sections. The same
happens if ``SYMBOL`` is actually defined with a ``#def`` directive.

Viceversa, one can also use ``#assumendef SYMBOL`` to declare that ``SYMBOL``
should be considered not defined, and hence skip ``#ifdef SYMBOL`` sections.

These features also work for declarations like ``#if defined(SYMBOL)`` and
boolean combinations of such declarations.

For instance, the following directive

.. code-block:: C
  #assumedef NVGRAPH_API

can be used to ignore the whole code block

.. code-block:: C
  #ifndef NVGRAPH_API
  #ifdef _WIN32
  #define NVGRAPH_API __stdcall
  #else
  #define NVGRAPH_API
  #endif
  #endif

which may otherwise confuse the c2nim parser.


``#private`` directive
----------------------

By default c2nim marks every top level identifier (proc name, variable, etc.)
as exported (the export marker is ``*`` in Nim). With the ``#private``
directive identifiers can be marked as private so that the resulting Nim
module does not export them. The ``#private`` directive takes a PEG pattern:

.. code-block:: C

  #private "@('_'!.)" // all identifiers ending in '_' are private

Note: The pattern refers to the original C identifiers, not to the resulting
identifiers after mangling!


``#skipcomments`` directive
---------------------------
**Note**: There is also a ``--skipcomments`` command line option that can be
used for the same purpose.

The ``#skipcomments`` directive can be put into the C code to make c2nim
ignore comments and not copy them into the generated Nim file.

``#headerprefix`` directive
--------------------------
**Note**: There is also a ``--headerprefix`` command line option that can be
used for the same purpose.

The ``#headerPrefix`` directive will append the raw string to beginning of C 
headers when generating import pragmas. This is useful for prepending the
include folders that many C projects use.

.. code-block:: C
  #headerPrefix "c_project/"

``#mergeBlocks`` directive
--------------------------
**Note**: There is also a ``--mergeBlocks`` command line option that can be
used for the same purpose.

The ``#mergeBlocks`` directive can be put into the C code to make c2nim
merge similar adjacent sections or "blocks" in the generated Nim code. This works for
a few kinds of blocks like ``let`` or ``var`` sections. This is helpful when importing
C code which produces lots of separate ``let`` sections.

``#mergeDuplicates`` directive
--------------------------
**Note**: There is also a ``--mergeDuplicates`` command line option that can be
used for the same purpose.

The ``#mergeDuplicates`` directive can be put into the C code to make c2nim
merge duplicate definitions. This is implemented naively so it can be slow.

``#delete`` directive
---------------------
**Note**: There is also a ``--delete:INDENT`` command line option that can be
used for the same purpose.

The ``#delete`` directive can be put into the C code to make c2nim delete 
certain code in the generated Nim code. For example this can be used to delete
specific variable in the generated Nim output. 

This is most useful when setting up scripts to automate updating wrapper files
for large C projects. Importing large headers can result in unwanted sections of
C code being translated. You can exclude these sections entirely or use it to embed
raw Nim code to fix small tricky bits of C code.

Note that the name should match the output Nim identifier names. In this example
the code produced by importing ``error_string_t`` will be deleted.

.. code-block:: C
  #nep1
  #delete ErrorStringT
  
  typedef error_string_t error_string_t;


Another use case is removing unwanted imports which C includes often
produce: 

.. code-block:: C
  #delete c_only_include
  include "c_only_include.h"

.. code-block:: Nim
  import c_only_include # this will be deleted


``#typeprefixes`` directive
---------------------------
**Note**: There is also a ``--typeprefixes`` command line option that can be
used for the same purpose.

**Note**: Instead you should use the ``--nep1`` command line option.

The ``#typeprefixes`` directive can be put into the C code to make c2nim
generate the ``T`` or ``P`` prefix for every defined type.


``#def`` directive
------------------

Often C code contains special macros that affect the declaration of a function
prototype but confuse c2nim's parser:

.. code-block:: C

  // does not parse!
  EXTERN(int) f(void);
  EXTERN(int) g(void);

Instead of removing ``EXTERN()`` from the input source file (which cannot be
done reliably even with a regular expression!), one can tell c2nim
that ``EXTERN`` is a macro that should be expanded by c2nim too:

.. code-block:: C

  #ifdef C2NIM
  #  def EXTERN(x) static x
  #endif
  // parses now!
  EXTERN(int) f(void);
  EXTERN(int) g(void);

``#def`` is very similar to C's ``#define``, so in general the macro definition
can be copied and pasted into a ``#def`` directive.

It can also be used when defines are being referred to, as c2nim currently does
not expand defines:

.. code-block:: C

  #define DEFINE_COMPLEX(R, C) typedef R C[2]

  #define DEFINE_API(X, R, C)   \
    DEFINE_COMPLEX(R, C);

  DEFINE_API(MANGLE_DOUBLE, double, my_complex);
..

The above example will fail, to ensure c2nim *processes* these defines and
expands them, use c2nim's ``#def`` directive:

.. code-block:: C

  #ifdef C2NIM
  #  def DEFINE_COMPLEX(R, C) typedef R C[2]
  #endif

  #ifndef C2NIM
  #  define DEFINE_COMPLEX(R, C) typedef R C[2]
  #endif

  #define DEFINE_API(X, R, C)   \
    DEFINE_COMPLEX(R, C);

  DEFINE_API(MANGLE_DOUBLE, double, my_complex);
..

Note: Ensure the original #define is not seen by c2nim (notice the #ifndef C2NIM).


``#pp`` directive
-----------------

Instead of keeping 2 versions of ``define foo`` around, one ``#def foo`` for
c2nim and one ordinary ``#define foo`` for C/C++, it is often more convenient
to tell c2nim that ``foo`` is to be interpreted as a ``#def``. This is what
the ``#pp`` directive accomplishes:

.. code-block:: C

  #ifdef C2NIM
  #pp DECLARE_NO_COPY_CLASS
  #endif

  #define DECLARE_NO_COPY_CLASS(classname)      \
    private:                                    \
        classname(const classname&);            \
        classname& operator=(const classname&)

In the example c2nim treats the declaration of ``DECLARE_NO_COPY_CLASS`` as
if it has been defined via ``#def``.


``#isarray`` directive
----------------------

C conflates pointers with arrays, Nim does not. To turn a pointer parameter's
type into Nim's ``ptr UncheckedArray`` type, use the ``#isarray`` directive:

.. code-block:: C

  #isarray a

  void sort(int* a, int len);


  Produces:

.. code-block:: Nim

  proc sort*(a: ptr UncheckedArray[cint]; len: cint)

``#render`` directive
---------------------
**Note**: There is also a ``--render:INDENT`` command line option that can be
used for the same purpose.

This option allows setting various render options. The list includes: 

* nobody
* nocomments
* doccomments
* nopragmas
* ids
* noprocdefs
* syms
* extranewlines
* reindentlongcomments


``#discardableprefix`` directive
--------------------------------

Often C and C++ code contains something like the following, where the return
value is frequently ignored and so the Nim wrapper should contain
a ``.discardable`` pragma:

.. code-block:: C

  bool AddPoint(Sizer* s, int x, int y);
  int SetSize(Widget* w, int w, int h);


This can be accomplished with the ``#discardableprefix`` directive. As its name
suggests functions of the given prefix(es) that have non-void return type get
annotated with ``.discardable``:

.. code-block:: C

  #discardableprefix Add
  #discardableprefix Set

  bool AddPoint(Sizer* s, int x, int y);
  int SetSize(Widget* w, int w, int h);

Produces:

.. code-block:: Nim

  proc AddPoint*(s: ptr Sizer; x: cint; y: cint): bool {.discardable.}
  proc SetSize*(w: ptr Widget; w: cint; h: cint): cint {.discardable.}

You can use ``#discardableprefix ""`` to *always* add the ``.discardable``
pragma since every name starts with the empty string prefix.


Embedding Nim code
==================

Starting with c2nim version 0.9.8 it is also possible to directly embed Nim
code in the C file. This is handy when you don't want to modify the generated
Nim code at all. Nim code can be embedded directly via ``#@ Nim code here @#``:

.. code-block:: C

  #ifdef C2NIM
  #@
  proc handwrittenNim(): string =
    "@#"
  @#
  #endif

The closing ``@#`` needs to be on a line of its own, only preceeded by
optional whitespace. This way ``@#`` can otherwise occur in the Nim code as
the example shows.

``#@ ... @#`` is syntactically treated as an **expression** so you can do pretty
wild stuff like:

.. code-block:: C

  #define foobar #@ 5 or 9
  @#

Produces:

.. code-block:: Nim

  const
    foobar* = 5 or 9


Instead of ``#@  @#`` the special brackets ``{|  |}`` can also be used, but
not nested since the ``|}`` doesn't have to be on a line of its own:

.. code-block:: C

  #define foobar {| 5 or 9 |}

C++ static method binding
=========================

With ``--cppBindStatic``, C++ static methods will be bound to their types
when possible:

.. code-block:: C++

   class ClassA
   {
     public:
       static void hello();
   };

Produces for ``hello``:

.. code-block:: Nim

   proc hello*(_: type ClassA)

   # which can be called like in CPP:
   ClassA.hello()

   # For static methods outside of classes, or when
   # --cppBindStatic is not present:
   proc hello*()
   hello()


Limitations
===========

* Lots of other small issues...
