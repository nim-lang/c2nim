#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import std / [strutils, os, times, md5, parseopt, strscans]

import compiler/ [llstream, ast, renderer, options, msgs, nversion]

import clexer, cparser, postprocessor

when declared(NimCompilerApiVersion):
  import compiler / [lineinfos, pathutils]

proc extractVersion(): string {.compileTime.} =
  let nimbleFile = staticRead("c2nim.nimble")
  for line in splitLines(nimbleFile):
    if scanf(line, "version$s=$s\"$+\"", result): break
  assert '.' in result

const
  Version = extractVersion()
  Usage = """
c2nim - C to Nim source converter
  (c) 2016 Andreas Rumpf
Usage: c2nim [options] [optionfile(s)] inputfile(s) [options]
  Optionfiles are C files with the 'c2nim' extension. These are parsed like
  other C files but produce no output file.
Options:
  -o, --out:FILE         set output filename
  --strict               do not produce an output file if an error occurred
  --cpp                  process C++ input file
  --dynlib:SYMBOL        import from dynlib: SYMBOL will be used for the import
  --header:HEADER_FILE   import from a HEADER_FILE (discouraged!)
  --header               import from the given header file
  --cdecl                annotate procs with ``{.cdecl.}``
  --noconv               annotate procs with ``{.noconv.}``
  --stdcall              annotate procs with ``{.stdcall.}``
  --importc              annotate procs with ``{.importc.}``
  --importdefines        import C defines as procs or vars with ``{.importc.}``
  --importfuncdefines    import C define funcs as procs with ``{.importc.}``
  --def:SYM='macro()'    define a C macro that gets replaced with the given
                         definition. It's parsed by the lexer. Use it to fix
                         function attributes: ``--def:PUBLIC='__attribute__ ()'``
  --reordercomments      reorder C comments to match Nim's postfix style
  --ref                  convert typ* to ref typ (default: ptr typ)
  --prefix:PREFIX        strip prefix for the generated Nim identifiers
                         (multiple --prefix options are supported)
  --suffix:SUFFIX        strip suffix for the generated Nim identifiers
                         (multiple --suffix options are supported)
  --mangle:PEG=FORMAT    extra PEG expression to mangle identifiers,
                         for example `--mangle:'{u?}int{\d+}_t=$1int$2'` to
                         convert C <stdint.h> to Nim equivalents
                         (multiple --mangle options are supported)
  --stdints              Mangle C stdint's into Nim style int's
  --paramprefix:PREFIX   add prefix to parameter name of the generated Nim proc
  --assumedef:IDENT      skips #ifndef sections for the given C identifier
                         (multiple --assumedef options are supported)
  --assumendef:IDENT     skips #ifdef sections for the given C identifier
                         (multiple --assumendef options are supported)
  --skipinclude          do not convert ``#include`` to ``import``
  --typeprefixes         generate ``T`` and ``P`` type prefixes
  --nep1                 follow 'NEP 1': Style Guide for Nim Code
  --skipcomments         do not copy comments
  --ignoreRValueRefs     translate C++'s ``T&&`` to ``T`` instead ``of var T``
  --keepBodies           keep C++'s method bodies
  --concat               concat the list of files into a single .nim file
  --debug                prints a c2nim stack trace in case of an error
  --exportdll:PREFIX     produce a DLL wrapping the C++ code
  -v, --version          write c2nim's version
  -h, --help             show this help
"""

proc isCppFile(s: string): bool =
  splitFile(s).ext.toLowerAscii in [".cpp", ".cxx", ".hpp"]

when not declared(NimCompilerApiVersion):
  type AbsoluteFile = string

proc parse(infile: string, options: PParserOptions; dllExport: var PNode): PNode =
  var stream = llStreamOpen(AbsoluteFile infile, fmRead)
  if stream == nil:
    when declared(NimCompilerApiVersion):
      rawMessage(gConfig, errGenerated, "cannot open file: " & infile)
    else:
      rawMessage(errGenerated, "cannot open file: " & infile)
  let isCpp = pfCpp notin options.flags and isCppFile(infile)
  var p: Parser
  if isCpp: options.flags.incl pfCpp
  openParser(p, infile, stream, options)
  result = parseUnit(p).postprocess(
    structStructMode = pfStructStruct in options.flags,
    reorderComments = pfReorderComments in options.flags
  )
  closeParser(p)
  if isCpp: options.flags.excl pfCpp
  if options.exportPrefix.len > 0:
    let dllprocs = exportAsDll(result, options.exportPrefix)
    assert dllprocs.kind == nkStmtList
    if dllExport.isNil:
      dllExport = dllprocs
    else:
      for x in dllprocs: dllExport.add x

proc isC2nimFile(s: string): bool = splitFile(s).ext.toLowerAscii == ".c2nim"

proc parseDefines(val: string): seq[ref Token] =
  let tpath = getTempDir() / "macro_" & getMD5(val) & ".h"
  let tfl = (open(tpath, fmReadWrite), tpath)
  let ss = llStreamOpen(val)
  var lex: Lexer
  openLexer(lex, tfl[1], ss)
  var tk = new Token
  var idx = 0
  result = newSeq[ref Token]()
  while tk.xkind != pxEof:
    tk = new Token
    lex.getTok(tk[])
    if tk.xkind == pxEof:
      break
    result.add tk
    inc idx
    if idx > 1_000: raise newException(Exception, "parse error")
  tfl[0].close()
  tfl[1].removeFile()

proc parseDefineArgs(parserOptions: var PParserOptions, val: string) =
  let defs = val.split("=")
  var mc: cparser.Macro
  let macs = parseDefines(defs[0])
  let toks = parseDefines(defs[1])
  mc.name = macs[0].s
  mc.params = -1
  mc.body = toks
  for m in macs[1..^1]:
    if m.xkind == pxParLe: mc.params = 0
    if m.xkind == pxSymbol: inc mc.params
  parserOptions.macros.add(mc)


var dummy: PNode

when not compiles(renderModule(dummy, "")):
  # newer versions of 'renderModule' take 2 parameters. We workaround this
  # problem here:
  proc renderModule(tree: PNode; filename: string, renderFlags: TRenderFlags) =
    renderModule(tree, filename, filename, renderFlags)

proc myRenderModule(tree: PNode; filename: string, renderFlags: TRenderFlags) =
  # also ensure we produced no trailing whitespace:
  let tmpFile = filename & ".tmp"
  renderModule(tree, tmpFile, renderFlags)

  let b = readFile(tmpFile)
  removeFile(tmpFile)
  let L = b.len
  var i = 0
  let f = open(filename, fmWrite)
  while i < L:
    let ch = b[i]
    if ch > ' ':
      f.write(ch)
    elif ch == ' ':
      let j = i
      while i < L and b[i] == ' ': inc i
      if i < L and b[i] == '\L':
        f.write('\L')
      else:
        for ii in j..i-1:
          f.write(' ')
        dec i
    elif ch == '\L':
      f.write('\L')
    else:
      f.write(ch)
    inc(i)
  f.close

proc main(infiles: seq[string], outfile: var string,
          options: PParserOptions, concat: bool) =
  var start = getTime()
  var dllexport: PNode = nil
  if concat:
    var tree = newNode(nkStmtList)
    for infile in infiles:
      let m = parse(infile.addFileExt("h"), options, dllexport)
      if not isC2nimFile(infile):
        if outfile.len == 0: outfile = changeFileExt(infile, "nim")
        for n in m: tree.add(n)
    myRenderModule(tree, outfile, options.renderFlags)
  else:
    for infile in infiles:
      let m = parse(infile, options, dllexport)
      if not isC2nimFile(infile):
        if outfile.len > 0:
          myRenderModule(m, outfile, options.renderFlags)
          outfile = ""
        else:
          let outfile = changeFileExt(infile, "nim")
          myRenderModule(m, outfile, options.renderFlags)
  if dllexport != nil:
    let (path, name, _) = infiles[0].splitFile
    let outfile = path / name & "_dllimpl" & ".nim"
    myRenderModule(dllexport, outfile, options.renderFlags)
  when declared(NimCompilerApiVersion):
    rawMessage(gConfig, hintSuccessX, [$gLinesCompiled, $(getTime() - start),
                              formatSize(getTotalMem()), ""])
  else:
    rawMessage(hintSuccessX, [$gLinesCompiled, $(getTime() - start),
                              formatSize(getTotalMem()), ""])

var
  infiles = newSeq[string](0)
  outfile = ""
  concat = false
  parserOptions = newParserOptions()
for kind, key, val in getopt():
  case kind
  of cmdArgument:
    infiles.add key
  of cmdLongOption, cmdShortOption:
    case key.normalize
    of "help", "h":
      stdout.write(Usage)
      quit(0)
    of "version", "v":
      stdout.write(Version & "\n")
      quit(0)
    of "o", "out": outfile = val
    of "concat": concat = true
    of "spliceheader":
      quit "[Error] 'spliceheader' doesn't exist anymore" &
           " use a list of files and --concat instead"
    of "exportdll":
      parserOptions.exportPrefix = val
    of "def":
      parserOptions.parseDefineArgs(val)
    else:
      if key.normalize == "render":
        if not parserOptions.renderFlags.setOption(val):
          quit("[Error] unknown option: " & key)
      elif not parserOptions.setOption(key, val):
        quit("[Error] unknown option: " & key)
  of cmdEnd: assert(false)
if infiles.len == 0:
  # no filename has been given, so we show the help:
  stdout.write(Usage)
else:
  main(infiles, outfile, parserOptions, concat)
