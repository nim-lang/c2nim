c2nim
=====

c2nim is a tool to translate Ansi C code to Nim. The output is human-readable
Nim code that is meant to be tweaked by hand after the translation process.
c2nim is no real compiler!

c2nim is preliminary meant to translate C header files. Because of this, the
preprocessor is part of the parser. For example:

```C
  #define abc 123
  #define xyz 789
```

Is translated into:

```Nimrod
  const
    abc* = 123
    xyz* = 789
```

c2nim is meant to translate fragments of C code and thus does not follow
include files. c2nim cannot parse all of Ansi C and many constructs cannot
be represented in Nim: for example *duff's device* cannot be translated to Nim.
