#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Algorithms for the abstract syntax tree: hash tables, lists
# and sets of nodes are supported. Efficiency is important as
# the data structures here are used in various places of the compiler.

import
  ast, hashes, tables, intsets, strutils, options, lineinfos, idents, msgs


# these are for debugging only: They are not really deprecated, but I want
# the warning so that release versions do not contain debugging statements:
proc debug*(n: PSym; conf: ConfigRef = nil) {.exportc: "debugSym", deprecated.}
proc debug*(n: PType; conf: ConfigRef = nil) {.exportc: "debugType", deprecated.}
proc debug*(n: PNode; conf: ConfigRef = nil) {.exportc: "debugNode", deprecated.}

template debug*(x: PSym|PType|PNode) {.deprecated.} =
  when compiles(c.config):
    debug(c.config, x)
  elif compiles(c.graph.config):
    debug(c.graph.config, x)
  else:
    error()

template debug*(x: auto) {.deprecated.} =
  echo x

template mdbg*: bool {.deprecated.} =
  when compiles(c.graph):
    c.module.fileIdx == c.graph.config.projectMainIdx
  elif compiles(c.module):
    c.module.fileIdx == c.config.projectMainIdx
  elif compiles(c.c.module):
    c.c.module.fileIdx == c.c.config.projectMainIdx
  elif compiles(m.c.module):
    m.c.module.fileIdx == m.c.config.projectMainIdx
  elif compiles(cl.c.module):
    cl.c.module.fileIdx == cl.c.config.projectMainIdx
  elif compiles(p):
    when compiles(p.lex):
      p.lex.fileIdx == p.lex.config.projectMainIdx
    else:
      p.module.module.fileIdx == p.config.projectMainIdx
  elif compiles(m.module.fileIdx):
    m.module.fileIdx == m.config.projectMainIdx
  elif compiles(L.fileIdx):
    L.fileIdx == L.config.projectMainIdx
  else:
    error()

proc lineInfoToStr(conf: ConfigRef; info: TLineInfo): string =
  format("[$1, $2, $3]", toFilename(conf, info), toLinenumber(info), toColumn(info))

const backrefStyle = "\e[90m"
const enumStyle = "\e[34m"
const numberStyle = "\e[33m"
const stringStyle = "\e[32m"
const resetStyle  = "\e[0m"

type
  DebugPrinter = object
    conf: ConfigRef
    visited: Table[pointer, int]
    renderSymType: bool
    indent: int
    currentLine: int
    firstItem: bool
    useColor: bool
    res: string

proc indentMore(this: var DebugPrinter) =
  this.indent += 2

proc indentLess(this: var DebugPrinter) =
  this.indent -= 2

proc newlineAndIndent(this: var DebugPrinter) =
  this.res.add "\n"
  this.currentLine += 1
  for i in 0..<this.indent:
    this.res.add ' '

proc openCurly(this: var DebugPrinter) =
  this.res.add "{"
  this.indentMore
  this.firstItem = true

proc closeCurly(this: var DebugPrinter) =
  this.indentLess
  this.newlineAndIndent
  this.res.add "}"

proc comma(this: var DebugPrinter) =
  this.res.add ", "

proc openBracket(this: var DebugPrinter) =
  this.res.add "["
  #this.indentMore

proc closeBracket(this: var DebugPrinter) =
  #this.indentLess
  this.res.add "]"

proc key(this: var DebugPrinter; key: string) =
  if not this.firstItem:
    this.res.add ","
  this.firstItem = false

  this.newlineAndIndent
  this.res.add "\""
  this.res.add key
  this.res.add "\": "

proc value(this: var DebugPrinter; value: string) =
  if this.useColor:
    this.res.add stringStyle
  this.res.add "\""
  this.res.add value
  this.res.add "\""
  if this.useColor:
    this.res.add resetStyle

proc value(this: var DebugPrinter; value: BiggestInt) =
  if this.useColor:
    this.res.add numberStyle
  this.res.addInt value
  if this.useColor:
    this.res.add resetStyle

proc value[T: enum](this: var DebugPrinter; value: T) =
  if this.useColor:
    this.res.add enumStyle
  this.res.add "\""
  this.res.add $value
  this.res.add "\""
  if this.useColor:
    this.res.add resetStyle

proc value[T: enum](this: var DebugPrinter; value: set[T]) =
  this.openBracket
  let high = card(value)-1
  var i = 0
  for v in value:
    this.value v
    if i != high:
      this.comma
    inc i
  this.closeBracket

template earlyExit(this: var DebugPrinter; n: PType | PNode | PSym) =
  if n == nil:
    this.res.add "null"
    return
  let index = this.visited.getOrDefault(cast[pointer](n), -1)
  if index < 0:
    this.visited[cast[pointer](n)] = this.currentLine
  else:
    if this.useColor:
      this.res.add backrefStyle
    this.res.add "<defined "
    this.res.addInt(this.currentLine - index)
    this.res.add " lines upwards>"
    if this.useColor:
      this.res.add resetStyle
    return

proc value(this: var DebugPrinter; value: PType)
proc value(this: var DebugPrinter; value: PNode)
proc value(this: var DebugPrinter; value: PSym) =
  earlyExit(this, value)

  this.openCurly
  this.key("kind")
  this.value(value.kind)
  this.key("name")
  this.value(value.name.s)
  this.key("id")
  this.value(value.id)
  if value.kind in {skField, skEnumField, skParam}:
    this.key("position")
    this.value(value.position)

  if card(value.flags) > 0:
    this.key("flags")
    this.value(value.flags)

  if this.renderSymType and value.typ != nil:
    this.key "typ"
    this.value(value.typ)

  this.closeCurly

proc value(this: var DebugPrinter; value: PType) =
  earlyExit(this, value)

  this.openCurly
  this.key "kind"
  this.value value.kind

  this.key "id"
  this.value value.id

  if value.sym != nil:
    this.key "sym"
    this.value value.sym
    #this.value value.sym.name.s

  if card(value.flags) > 0:
    this.key "flags"
    this.value value.flags

  if value.kind in IntegralTypes and value.n != nil:
    this.key "n"
    this.value value.n

  if value.len > 0:
    this.key "sons"
    this.openBracket
    for i in 0..<value.len:
      this.value value[i]
      if i != value.len - 1:
        this.comma
    this.closeBracket

  if value.n != nil:
    this.key "n"
    this.value value.n

  this.closeCurly

proc value(this: var DebugPrinter; value: PNode) =
  earlyExit(this, value)

  this.openCurly
  this.key "kind"
  this.value  value.kind
  if value.comment.len > 0:
    this.key "comment"
    this.value  value.comment
  when defined(useNodeIds):
    this.key "id"
    this.value value.id
  if this.conf != nil:
    this.key "info"
    this.value $lineInfoToStr(this.conf, value.info)
  if value.flags != {}:
    this.key "flags"
    this.value value.flags

  if value.typ != nil:
    this.key "typ"
    this.value value.typ.kind
  else:
    this.key "typ"
    this.value "nil"

  case value.kind
  of nkCharLit..nkUInt64Lit:
    this.key "intVal"
    this.value value.strVal
  of nkFloatLit, nkFloat32Lit, nkFloat64Lit:
    this.key "floatVal"
    this.value value.strVal
  of nkStrLit..nkTripleStrLit:
    this.key "strVal"
    this.value value.strVal
  of nkSym:
    this.key "sym"
    this.value value.sym
    #this.value value.sym.name.s
  of nkIdent:
    if value.ident != nil:
      this.key "ident"
      this.value value.ident.s
  else:
    if this.renderSymType and value.typ != nil:
      this.key "typ"
      this.value value.typ
    if value.len > 0:
      this.key "sons"
      this.openBracket
      for i in 0..<value.len:
        this.value value[i]
        if i != value.len - 1:
          this.comma
      this.closeBracket

  this.closeCurly


proc debug(n: PSym; conf: ConfigRef) =
  var this: DebugPrinter
  this.visited = initTable[pointer, int]()
  this.renderSymType = true
  this.useColor = not defined(windows)
  this.value(n)
  echo($this.res)

proc debug(n: PType; conf: ConfigRef) =
  var this: DebugPrinter
  this.visited = initTable[pointer, int]()
  this.renderSymType = true
  this.useColor = not defined(windows)
  this.value(n)
  echo($this.res)

proc debug(n: PNode; conf: ConfigRef) =
  var this: DebugPrinter
  this.visited = initTable[pointer, int]()
  #this.renderSymType = true
  this.useColor = not defined(windows)
  this.value(n)
  echo($this.res)
