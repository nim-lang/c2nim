#
#
#           The Nim Compiler
#        (c) Copyright 2018 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Path handling utilities for Nim. Strictly typed code in order
## to avoid the never ending time sink in getting path handling right.

import os, pathnorm

type
  AbsoluteFile* = distinct string
  AbsoluteDir* = distinct string
  RelativeFile* = distinct string
  RelativeDir* = distinct string
  AnyPath* = AbsoluteFile|AbsoluteDir|RelativeFile|RelativeDir

proc isEmpty*(x: AnyPath): bool {.inline.} = x.string.len == 0

proc copyFile*(source, dest: AbsoluteFile) =
  os.copyFile(source.string, dest.string)

proc removeFile*(x: AbsoluteFile) {.borrow.}

proc splitFile*(x: AbsoluteFile): tuple[dir: AbsoluteDir, name, ext: string] =
  let (a, b, c) = splitFile(x.string)
  result = (dir: AbsoluteDir(a), name: b, ext: c)

proc extractFilename*(x: AbsoluteFile): string {.borrow.}

proc fileExists*(x: AbsoluteFile): bool {.borrow.}
proc dirExists*(x: AbsoluteDir): bool {.borrow.}

proc quoteShell*(x: AbsoluteFile): string {.borrow.}
proc quoteShell*(x: AbsoluteDir): string {.borrow.}

proc cmpPaths*(x, y: AbsoluteDir): int {.borrow.}

proc createDir*(x: AbsoluteDir) {.borrow.}

proc toAbsoluteDir*(path: string): AbsoluteDir =
  result = if path.isAbsolute: AbsoluteDir(path)
           else: AbsoluteDir(getCurrentDir() / path)

proc `$`*(x: AnyPath): string = x.string

when true:
  proc eqImpl(x, y: string): bool {.inline.} =
    result = cmpPaths(x, y) == 0

  proc `==`*[T: AnyPath](x, y: T): bool = eqImpl(x.string, y.string)

  template postProcessBase(base: AbsoluteDir): untyped =
    # xxx: as argued here https://github.com/nim-lang/Nim/pull/10018#issuecomment-448192956
    # empty paths should not mean `cwd` so the correct behavior would be to throw
    # here and make sure `outDir` is always correctly initialized; for now
    # we simply preserve pre-existing external semantics and treat it as `cwd`
    when false:
      doAssert isAbsolute(base.string), base.string
      base
    else:
      if base.isEmpty: getCurrentDir().AbsoluteDir else: base

  proc `/`*(base: AbsoluteDir; f: RelativeFile): AbsoluteFile =
    let base = postProcessBase(base)
    assert(not isAbsolute(f.string), f.string)
    result = AbsoluteFile newStringOfCap(base.string.len + f.string.len)
    var state = 0
    addNormalizePath(base.string, result.string, state)
    addNormalizePath(f.string, result.string, state)

  proc `/`*(base: AbsoluteDir; f: RelativeDir): AbsoluteDir =
    let base = postProcessBase(base)
    assert(not isAbsolute(f.string))
    result = AbsoluteDir newStringOfCap(base.string.len + f.string.len)
    var state = 0
    addNormalizePath(base.string, result.string, state)
    addNormalizePath(f.string, result.string, state)

  proc relativeTo*(fullPath: AbsoluteFile, baseFilename: AbsoluteDir;
                   sep = DirSep): RelativeFile =
    # this currently fails for `tests/compilerapi/tcompilerapi.nim`
    # it's needed otherwise would returns an absolute path
    # assert not baseFilename.isEmpty, $fullPath
    result = RelativeFile(relativePath(fullPath.string, baseFilename.string, sep))

  proc toAbsolute*(file: string; base: AbsoluteDir): AbsoluteFile =
    if isAbsolute(file): result = AbsoluteFile(file)
    else: result = base / RelativeFile file

  proc changeFileExt*(x: AbsoluteFile; ext: string): AbsoluteFile {.borrow.}
  proc changeFileExt*(x: RelativeFile; ext: string): RelativeFile {.borrow.}

  proc addFileExt*(x: AbsoluteFile; ext: string): AbsoluteFile {.borrow.}
  proc addFileExt*(x: RelativeFile; ext: string): RelativeFile {.borrow.}

  proc writeFile*(x: AbsoluteFile; content: string) {.borrow.}
