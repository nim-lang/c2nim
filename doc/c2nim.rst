=======================
  c2nim User's manual
=======================

:Author: Andreas Rumpf
:Version: |nimversion|

.. contents::

Introduction
============

  "We all make choices. But in the end our choices make us."


c2nim is a tool to translate Ansi C code to Nim. The output is
human-readable Nim code that is meant to be tweaked by hand after the
translation process. c2nim is no real compiler!

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
include files. c2nim cannot parse all of Ansi C and many constructs cannot
be represented in Nim: for example `duff's device`:idx: cannot be translated
to Nim.


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
    template OUT*(x: expr): stmt =
      discard

As can be seen from the example, C's macros with parameters are mapped
to Nim's templates. This mapping is the best one can do, but it is of course
not accurate: Nim's templates operate on syntax trees whereas C's
macros work on the token level. c2nim cannot translate any macro that contains
the ``##`` token concatenation operator.

c2nim's preprocessor supports special directives that affect how the output
is generated. They should be put into a ``#ifdef C2NIM`` section so that
ordinary C compilers ignore them.


``#skipinclude`` directive
--------------------------
**Note**: There is also a ``--skipinclude`` command line option that can be
used for the same purpose.

By default, c2nim translates an ``#include`` that is not followed by ``<``
(like in ``#include <stdlib>``) to a Nim ``import`` statement. This
directive tells c2nim to just skip any ``#include``.


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

This directive tells c2nim that it should annotate every proc that resulted
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

The ``#header`` directive tells c2nim that it should annotate every proc that
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


``#typeprefixes`` directive
---------------------------
**Note**: There is also a ``--typeprefixes`` command line option that can be
used for the same purpose.

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


Instead of ``#@  @#`` Nim's pragma brackets ``{.  .}`` can also be used, but
not nested since the ``.}`` doesn't have to be on a line of its own:

.. code-block:: C

  #define foobar {. 5 or 9 .}



Limitations
===========

* C's ``,`` operator (comma operator) is not supported.
* C's ``union`` are translated to Nim's objects and only the first field
  is included in the object type. This way there is a high chance that it is
  binary compatible to the union.
* The condition in a ``do while(condition)`` statement must be ``0``.
* Lots of other small issues...
