#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import
  strutils, os, times, parseopt, compiler/llstream, compiler/ast,
  compiler/renderer, compiler/options, compiler/msgs,
  clex, cparse, postprocessor

const
  Version = "0.9.9" # keep in sync with Nimble version. D'oh!
  Usage = """
c2nim - C to Nim source converter
  Version """ & $Version & " [" & $hostOS & ": " & $hostCPU & """]
  Copyright (c) 2015 Andreas Rumpf
Usage: c2nim [options] [optionfile(s)] inputfile(s) [options]
  Optionfiles are C files with the 'c2nim' extension. These are parsed like
  other C files but produce no output file.
Options:
  -o, --out:FILE         set output filename
  --cpp                  process C++ input file
  --dynlib:SYMBOL        import from dynlib: SYMBOL will be used for the import
  --header:HEADER_FILE   import from a HEADER_FILE (discouraged!)
  --header               import from the given header file
  --cdecl                annotate procs with ``{.cdecl.}``
  --stdcall              annotate procs with ``{.stdcall.}``
  --ref                  convert typ* to ref typ (default: ptr typ)
  --prefix:PREFIX        strip prefix for the generated Nim identifiers
                         (multiple --prefix options are supported)
  --suffix:SUFFIX        strip suffix for the generated Nim identifiers
                         (multiple --suffix options are supported)
  --skipinclude          do not convert ``#include`` to ``import``
  --typeprefixes         generate ``T`` and ``P`` type prefixes
  --nep1                 follow 'NEP 1': Style Guide for Nim Code
  --skipcomments         do not copy comments
  --ignoreRValueRefs     translate C++'s ``T&&`` to ``T`` instead ``of var T``
  --keepBodies           keep C++'s method bodies
  --concat               concat the list of files into a single .nim file
  --debug                prints a c2nim stack trace in case of an error
  -v, --version          write c2nim's version
  -h, --help             show this help
"""

proc parse(infile: string, options: PParserOptions): PNode =
  var stream = llStreamOpen(infile, fmRead)
  if stream == nil: rawMessage(errCannotOpenFile, infile)
  var p: Parser
  openParser(p, infile, stream, options)
  result = parseUnit(p).postprocess
  closeParser(p)

proc isC2nimFile(s: string): bool = splitFile(s).ext.toLowerAscii == ".c2nim"

proc main(infiles: seq[string], outfile: var string,
          options: PParserOptions, concat: bool) =
  var start = getTime()
  if concat:
    var tree = newNode(nkStmtList)
    for infile in infiles:
      let m = parse(infile.addFileExt("h"), options)
      if not isC2nimFile(infile):
        if outfile.len == 0: outfile = changeFileExt(infile, "nim")
        for n in m: tree.add(n)
    renderModule(tree, outfile)
  else:
    for infile in infiles:
      let m = parse(infile, options)
      if not isC2nimFile(infile):
        if outfile.len > 0:
          renderModule(m, outfile)
          outfile = ""
        else:
          renderModule(m, changeFileExt(infile, "nim"))
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
    else:
      if not parserOptions.setOption(key, val):
        stdout.writeline("[Error] unknown option: " & key)
  of cmdEnd: assert(false)
if infiles.len == 0:
  # no filename has been given, so we show the help:
  stdout.write(Usage)
else:
  main(infiles, outfile, parserOptions, concat)
