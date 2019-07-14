#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements an Ansi C / C++ parser.
## It translates a C source file into a Nim AST. Then the renderer can be
## used to convert the AST to its text representation.

# TODO
# - implement handling of '::': function declarations
# - support '#if' in classes

import
  os, compiler/llstream, compiler/renderer, clex, compiler/idents, strutils,
  pegs, compiler/ast, compiler/msgs,
  strtabs, hashes, algorithm, compiler/nversion

when declared(NimCompilerApiVersion):
  import compiler / lineinfos

  proc getIdent(s: string): PIdent = getIdent(identCache, s)
  template emptyNode: untyped = newNode(nkEmpty)

import pegs except Token, Tokkind

type
  ParserFlag* = enum
    pfRefs,             ## use "ref" instead of "ptr" for C's typ*
    pfCDecl,            ## annotate procs with cdecl
    pfStdCall,          ## annotate procs with stdcall
    pfSkipInclude,      ## skip all ``#include``
    pfTypePrefixes,     ## all generated types start with 'T' or 'P'
    pfSkipComments,     ## do not generate comments
    pfCpp,              ## process C++
    pfIgnoreRValueRefs, ## transform C++'s 'T&&' to 'T'
    pfKeepBodies,       ## do not skip C++ method bodies
    pfAssumeIfIsTrue,   ## assume #if is true
    pfStructStruct      ## do not treat struct Foo Foo as a forward decl

  Macro = object
    name: string
    params: int # number of parameters; 0 for empty (); -1 for no () at all
    body: seq[ref Token] # can contain pxMacroParam tokens

  ParserOptions = object ## shared parser state!
    flags*: set[ParserFlag]
    prefixes, suffixes: seq[string]
    assumeDef, assumenDef: seq[string]
    mangleRules: seq[tuple[pattern: Peg, frmt: string]]
    privateRules: seq[Peg]
    dynlibSym, headerOverride: string
    macros: seq[Macro]
    toMangle: StringTableRef
    classes: StringTableRef
    toPreprocess: StringTableRef
    inheritable: StringTableRef
    debugMode, followNep1, useHeader: bool
    discardablePrefixes: seq[string]
    constructor, destructor, importcLit: string
    exportPrefix*: string
    paramPrefix*: string

  PParserOptions* = ref ParserOptions

  Parser* = object
    lex: Lexer
    tok: ref Token       # current token
    header: string
    options: PParserOptions
    backtrack: seq[ref Token]
    inTypeDef: int
    scopeCounter: int
    hasDeadCodeElimPragma: bool
    currentClass: PNode   # type that needs to be added as 'this' parameter
    currentClassOrig: string # original class name
    currentNamespace: string
    inAngleBracket: int
    lastConstType: PNode # another hack to be able to translate 'const Foo& foo'
                         # to 'foo: Foo' and not 'foo: var Foo'.

  ReplaceTuple* = array[0..1, string]

  ERetryParsing = object of Exception

  SectionParser = proc(p: var Parser): PNode {.nimcall.}

proc parseDir(p: var Parser; sectionParser: SectionParser): PNode
proc addTypeDef(section, name, t, genericParams: PNode)
proc parseStruct(p: var Parser, stmtList: PNode, isUnion: bool): PNode
proc parseStructBody(p: var Parser, stmtList: PNode, isUnion: bool,
                     kind: TNodeKind = nkRecList): PNode

proc newParserOptions*(): PParserOptions =
  new(result)
  result.prefixes = @[]
  result.suffixes = @[]
  result.assumeDef = @[]
  result.assumenDef = @["__cplusplus"]
  result.macros = @[]
  result.mangleRules = @[]
  result.privateRules = @[]
  result.discardablePrefixes = @[]
  result.flags = {}
  result.dynlibSym = ""
  result.headerOverride = ""
  result.toMangle = newStringTable(modeCaseSensitive)
  result.classes = newStringTable(modeCaseSensitive)
  result.toPreprocess = newStringTable(modeCaseSensitive)
  result.inheritable = newStringTable(modeCaseSensitive)
  result.constructor = "construct"
  result.destructor = "destroy"
  result.importcLit = "importc"
  result.exportPrefix = ""
  result.paramPrefix = "a"

proc setOption*(parserOptions: PParserOptions, key: string, val=""): bool =
  result = true
  case key.normalize
  of "ref": incl(parserOptions.flags, pfRefs)
  of "dynlib": parserOptions.dynlibSym = val
  of "header":
    parserOptions.useHeader = true
    if val.len > 0: parserOptions.headerOverride = val
  of "cdecl": incl(parserOptions.flags, pfCdecl)
  of "stdcall": incl(parserOptions.flags, pfStdCall)
  of "prefix": parserOptions.prefixes.add(val)
  of "suffix": parserOptions.suffixes.add(val)
  of "paramprefix":
    if val.len > 0: parserOptions.paramPrefix = val
  of "assumedef": parserOptions.assumeDef.add(val)
  of "assumendef": parserOptions.assumenDef.add(val)
  of "skipinclude": incl(parserOptions.flags, pfSkipInclude)
  of "typeprefixes": incl(parserOptions.flags, pfTypePrefixes)
  of "skipcomments": incl(parserOptions.flags, pfSkipComments)
  of "cpp":
    incl(parserOptions.flags, pfCpp)
    parserOptions.importcLit = "importcpp"
  of "keepbodies": incl(parserOptions.flags, pfKeepBodies)
  of "ignorervaluerefs": incl(parserOptions.flags, pfIgnoreRValueRefs)
  of "class": parserOptions.classes[val] = "true"
  of "debug": parserOptions.debugMode = true
  of "nep1": parserOptions.followNep1 = true
  of "constructor": parserOptions.constructor = val
  of "destructor": parserOptions.destructor = val
  of "assumeifistrue": incl(parserOptions.flags, pfAssumeIfIsTrue)
  of "discardableprefix": parserOptions.discardablePrefixes.add(val)
  of "structstruct": incl(parserOptions.flags, pfStructStruct)
  else: result = false

proc parseUnit*(p: var Parser): PNode

proc openParser*(p: var Parser, filename: string,
                inputStream: PLLStream, options = newParserOptions()) =
  openLexer(p.lex, filename, inputStream)
  p.options = options
  p.header = filename.extractFilename
  p.lex.debugMode = options.debugMode
  p.backtrack = @[]
  p.currentNamespace = ""
  p.currentClassOrig = ""
  new(p.tok)

proc parMessage(p: Parser, msg: TMsgKind, arg = "") =
  lexMessage(p.lex, msg, arg)

proc closeParser*(p: var Parser) = closeLexer(p.lex)
proc saveContext(p: var Parser) = p.backtrack.add(p.tok)
# EITHER call 'closeContext' or 'backtrackContext':
proc closeContext(p: var Parser) = discard p.backtrack.pop()
proc backtrackContext(p: var Parser) = p.tok = p.backtrack.pop()

proc rawGetTok(p: var Parser) =
  if p.tok.next != nil:
    p.tok = p.tok.next
  elif p.backtrack.len == 0:
    p.tok.next = nil
    getTok(p.lex, p.tok[])
  else:
    # We need the next token and must be able to backtrack. So we need to
    # allocate a new token.
    var t: ref Token
    new(t)
    getTok(p.lex, t[])
    p.tok.next = t
    p.tok = t

proc insertAngleRi(currentToken: ref Token) =
  var t: ref Token
  new(t)
  t.xkind = pxAngleRi
  t.next = currentToken.next
  currentToken.next = t

proc findMacro(p: Parser): int =
  for i in 0..high(p.options.macros):
    if p.tok.s == p.options.macros[i].name: return i
  return -1

proc rawEat(p: var Parser, xkind: Tokkind) =
  if p.tok.xkind == xkind: rawGetTok(p)
  else: parMessage(p, errGenerated, "token expected: " & tokKindToStr(xkind))

proc parseMacroArguments(p: var Parser): seq[seq[ref Token]] =
  result = @[]
  result.add(@[])
  var i: array[pxParLe..pxCurlyLe, int]
  var L = 0
  # we push a context here, so that no token will be overwritten, but we get
  # fresh tokens instead:
  saveContext(p)
  while true:
    var kind = p.tok.xkind
    case kind
    of pxEof: rawEat(p, pxParRi)
    of pxParLe, pxBracketLe, pxCurlyLe:
      inc(i[kind])
      result[L].add(p.tok)
    of pxParRi:
      # end of arguments?
      if i[pxParLe] == 0 and i[pxBracketLe] == 0 and i[pxCurlyLe] == 0: break
      if i[pxParLe] > 0: dec(i[pxParLe])
      result[L].add(p.tok)
    of pxBracketRi, pxCurlyRi:
      kind = pred(kind, 3)
      if i[kind] > 0: dec(i[kind])
      result[L].add(p.tok)
    of pxComma:
      if i[pxParLe] == 0 and i[pxBracketLe] == 0 and i[pxCurlyLe] == 0:
        # next argument: comma is not part of the argument
        result.add(@[])
        inc(L)
      else:
        # comma does not separate different arguments:
        result[L].add(p.tok)
    else:
      result[L].add(p.tok)
    rawGetTok(p)
  closeContext(p)

proc expandMacro(p: var Parser, m: Macro) =
  rawGetTok(p) # skip macro name
  var arguments: seq[seq[ref Token]]
  if m.params >= 0:
    rawEat(p, pxParLe)
    if m.params > 0:
      arguments = parseMacroArguments(p)
      if arguments.len != m.params:
        parMessage(p, errGenerated, "wrong number of arguments")
    rawEat(p, pxParRi)
  # insert into the token list:
  if m.body.len > 0:
    var newList: ref Token
    new(newList)
    var lastTok = newList
    var mergeToken = false
    template appendTok(t) {.dirty.} =
      if mergeToken:
        mergeToken = false
        lastTok.s &= t.s
      else:
        lastTok.next = t
        lastTok = t

    for tok in items(m.body):
      if tok.xkind == pxMacroParam:
        # it can happen that parameters are expanded multiple times:
        # #def foo(x) x x
        # Therefore we have to copy the token here to avoid wrong aliasing
        # that leads to an invalid token sequence:
        for t in items(arguments[int(tok.iNumber)]):
          var newToken: ref Token
          new(newToken); newToken[] = t[]
          appendTok(newToken)
      elif tok.xkind == pxDirConc:
        # implement token merging:
        mergeToken = true
      elif tok.xkind == pxMacroParamToStr:
        var newToken: ref Token
        new(newToken)
        newToken.xkind = pxStrLit; newToken.s = ""
        for t in items(arguments[int(tok.iNumber)]):
          newToken.s &= $t[]
        appendTok(newToken)
      else:
        appendTok(tok)
    lastTok.next = p.tok
    p.tok = newList.next

proc getTok(p: var Parser) =
  rawGetTok(p)
  while p.tok.xkind == pxSymbol:
    var idx = findMacro(p)
    if idx >= 0:
      expandMacro(p, p.options.macros[idx])
    else:
      break

proc parLineInfo(p: Parser): TLineInfo =
  result = getLineInfo(p.lex)

proc skipComAux(p: var Parser, n: PNode) =
  if n != nil and n.kind != nkEmpty:
    if pfSkipComments notin p.options.flags:
      if n.comment.len == 0: n.comment = p.tok.s
      else: add(n.comment, "\n" & p.tok.s)
  else:
    parMessage(p, warnCommentXIgnored, p.tok.s)
  getTok(p)

proc skipCom(p: var Parser, n: PNode) =
  while p.tok.xkind in {pxLineComment, pxStarComment}: skipComAux(p, n)

proc skipStarCom(p: var Parser, n: PNode) =
  while p.tok.xkind == pxStarComment: skipComAux(p, n)

proc getTok(p: var Parser, n: PNode) =
  getTok(p)
  skipCom(p, n)

proc expectIdent(p: Parser) =
  if p.tok.xkind != pxSymbol:
    parMessage(p, errGenerated, "identifier expected, but got: " & debugTok(p.lex, p.tok[]))

proc eat(p: var Parser, xkind: Tokkind, n: PNode) =
  if p.tok.xkind == xkind: getTok(p, n)
  else: parMessage(p, errGenerated, "token expected: " & tokKindToStr(xkind))

proc eat(p: var Parser, xkind: Tokkind) =
  if p.tok.xkind == xkind: getTok(p)
  else: parMessage(p, errGenerated, "token expected: " & tokKindToStr(xkind))

proc eat(p: var Parser, tok: string, n: PNode) =
  if p.tok.s == tok: getTok(p, n)
  else: parMessage(p, errGenerated, "token expected: " & tok)

proc opt(p: var Parser, xkind: Tokkind, n: PNode) =
  if p.tok.xkind == xkind: getTok(p, n)

proc addSon(father, a, b: PNode) =
  addSon(father, a)
  addSon(father, b)

proc addSon(father, a, b, c: PNode) =
  addSon(father, a)
  addSon(father, b)
  addSon(father, c)

proc newNodeP(kind: TNodeKind, p: Parser): PNode =
  result = newNodeI(kind, getLineInfo(p.lex))

proc newIntNodeP(kind: TNodeKind, intVal: BiggestInt, p: Parser): PNode =
  result = newNodeP(kind, p)
  result.intVal = intVal

proc newFloatNodeP(kind: TNodeKind, floatVal: BiggestFloat,
                   p: Parser): PNode =
  result = newNodeP(kind, p)
  result.floatVal = floatVal

proc newStrNodeP(kind: TNodeKind, strVal: string, p: Parser): PNode =
  result = newNodeP(kind, p)
  result.strVal = strVal

proc newIdentNodeP(ident: PIdent, p: Parser): PNode =
  result = newNodeP(nkIdent, p)
  result.ident = ident

proc newIdentNodeP(ident: string, p: Parser): PNode =
  assert(not (ident.len == 0))
  result = newIdentNodeP(getIdent(ident), p)

proc newIdentPair(a, b: string, p: Parser): PNode =
  result = newNodeP(nkExprColonExpr, p)
  addSon(result, newIdentNodeP(a, p))
  addSon(result, newIdentNodeP(b, p))

proc newIdentStrLitPair(a, b: string, p: Parser): PNode =
  result = newNodeP(nkExprColonExpr, p)
  addSon(result, newIdentNodeP(a, p))
  addSon(result, newStrNodeP(nkStrLit, b, p))

include rules

proc newBinary(opr: string, a, b: PNode, p: Parser): PNode =
  result = newNodeP(nkInfix, p)
  addSon(result, newIdentNodeP(getIdent(opr), p))
  addSon(result, a)
  addSon(result, b)

proc skipIdent(p: var Parser; kind: TSymKind): PNode =
  expectIdent(p)
  result = mangledIdent(p.tok.s, p, kind)
  getTok(p, result)

proc skipIdentExport(p: var Parser; kind: TSymKind): PNode =
  expectIdent(p)
  result = exportSym(p, mangledIdent(p.tok.s, p, kind), p.tok.s)
  getTok(p, result)

proc markTypeIdent(p: var Parser, typ: PNode) =
  if pfTypePrefixes in p.options.flags:
    var prefix = ""
    if typ == nil or typ.kind == nkEmpty:
      prefix = "T"
    else:
      var t = typ
      while t != nil and t.kind in {nkVarTy, nkPtrTy, nkRefTy}:
        prefix.add('P')
        t = t.sons[0]
      if prefix.len == 0: prefix.add('T')
    expectIdent(p)
    p.options.toMangle[p.tok.s] = prefix & mangleRules(p.tok.s, p, skType)

# --------------- parser -----------------------------------------------------
# We use this parsing rule: If it looks like a declaration, it is one. This
# avoids to build a symbol table, which can't be done reliably anyway for our
# purposes.

proc expression(p: var Parser, rbp: int = 0): PNode
proc constantExpression(p: var Parser): PNode = expression(p, 40)
proc assignmentExpression(p: var Parser): PNode = expression(p, 30)
proc compoundStatement(p: var Parser; newScope=true): PNode
proc statement(p: var Parser): PNode

proc declKeyword(p: Parser, s: string): bool =
  # returns true if it is a keyword that introduces a declaration
  case s
  of  "extern", "static", "auto", "register", "const", "constexpr", "volatile",
      "restrict", "inline", "__inline", "__cdecl", "__stdcall", "__syscall",
      "__fastcall", "__safecall", "void", "struct", "union", "enum", "typedef",
      "size_t", "short", "int", "long", "float", "double", "signed", "unsigned",
      "char":
    result = true
  of "class", "mutable":
    result = p.options.flags.contains(pfCpp)
  else: discard

proc stmtKeyword(s: string): bool =
  case s
  of  "if", "for", "while", "do", "switch", "break", "continue", "return",
      "goto":
    result = true
  else: discard

# ------------------- type desc -----------------------------------------------

proc typeDesc(p: var Parser): PNode

proc isIntType(s: string): bool =
  case s
  of "short", "int", "long", "float", "double", "signed", "unsigned", "size_t":
    result = true
  else: discard

proc skipConst(p: var Parser): bool {.discardable.} =
  while p.tok.xkind == pxSymbol and
      (p.tok.s == "const" or p.tok.s == "constexpr" or p.tok.s == "volatile" or
       p.tok.s == "restrict" or (p.tok.s == "mutable" and
        pfCpp in p.options.flags)):
    if p.tok.s == "const": result = true
    getTok(p, nil)

proc isTemplateAngleBracket(p: var Parser): bool =
  if pfCpp notin p.options.flags: return false
  saveContext(p)
  getTok(p, nil) # skip "<"
  var i: array[pxParLe..pxCurlyLe, int]
  var angles = 0
  while true:
    let kind = p.tok.xkind
    case kind
    of pxEof: break
    of pxParLe, pxBracketLe, pxCurlyLe: inc(i[kind])
    of pxGt, pxAngleRi:
      # end of arguments?
      if i[pxParLe] == 0 and i[pxBracketLe] == 0 and i[pxCurlyLe] == 0 and
          angles == 0:
        # mark as end token:
        p.tok.xkind = pxAngleRi
        result = true;
        break
      if angles > 0: dec(angles)
    of pxShr:
      # >> can end a template too:
      if i[pxParLe] == 0 and i[pxBracketLe] == 0 and i[pxCurlyLe] == 0 and
          angles == 1:
        p.tok.xkind = pxAngleRi
        insertAngleRi(p.tok)
        result = true
        break
      if angles > 1: dec(angles, 2)
    of pxLt: inc(angles)
    of pxParRi, pxBracketRi, pxCurlyRi:
      let kind = pred(kind, 3)
      if i[kind] > 0: dec(i[kind])
      else: break
    of pxSemicolon: break
    else: discard
    getTok(p, nil)
  backtrackContext(p)

proc optScope(p: var Parser, n: PNode; kind: TSymKind): PNode =
  result = n
  if pfCpp in p.options.flags:
    while p.tok.xkind == pxScope:
      when true:
        getTok(p, result)
        expectIdent(p)
        result = mangledIdent(p.tok.s, p, kind)
      else:
        let a = result
        result = newNodeP(nkDotExpr, p)
        result.add(a)
        getTok(p, result)
        expectIdent(p)
        result.add(mangledIdent(p.tok.s, p, kind))
      getTok(p, result)

proc optAngle(p: var Parser, n: PNode): PNode =
  if p.tok.xkind == pxLt and isTemplateAngleBracket(p):
    getTok(p)
    result = newNodeP(nkBracketExpr, p)
    result.add(n)
    inc p.inAngleBracket
    while true:
      let a = if p.tok.xkind == pxSymbol: typeDesc(p)
              else: assignmentExpression(p)
      if not a.isNil: result.add(a)
      if p.tok.xkind != pxComma: break
      getTok(p)
    dec p.inAngleBracket
    eat(p, pxAngleRi)
    result = optScope(p, result, skType)
  else:
    result = n

proc typeAtom(p: var Parser): PNode =
  var isConst = skipConst(p)
  expectIdent(p)
  case p.tok.s
  of "void":
    result = newNodeP(nkNilLit, p) # little hack
    getTok(p, nil)
  of "struct", "union", "enum":
    getTok(p, nil)
    result = skipIdent(p, skType)
  elif isIntType(p.tok.s):
    var x = ""
    #getTok(p, nil)
    var isUnsigned = false
    var isSizeT = false
    while p.tok.xkind == pxSymbol and (isIntType(p.tok.s) or p.tok.s == "char"):
      if p.tok.s == "unsigned":
        isUnsigned = true
      elif p.tok.s == "size_t":
        isSizeT = true
      elif p.tok.s == "signed" or p.tok.s == "int":
        discard
      else:
        add(x, p.tok.s)
      getTok(p, nil)
      if skipConst(p): isConst = true
    if x.len == 0: x = "int"
    let xx = if isSizeT: "csize" elif isUnsigned: "cu" & x else: "c" & x
    result = mangledIdent(xx, p, skDontMangle)
  else:
    result = mangledIdent(p.tok.s, p, skType)
    getTok(p, result)
    result = optScope(p, result, skType)
    result = optAngle(p, result)
  if isConst: p.lastConstType = result

proc newPointerTy(p: Parser, typ: PNode): PNode =
  if pfRefs in p.options.flags:
    result = newNodeP(nkRefTy, p)
  else:
    result = newNodeP(nkPtrTy, p)
  result.addSon(typ)

proc pointer(p: var Parser, a: PNode): PNode =
  result = a
  var i = 0
  let isConstA = skipConst(p)
  while true:
    if p.tok.xkind == pxStar:
      inc(i)
      getTok(p, result)
      skipConst(p)
      result = newPointerTy(p, result)
    elif p.tok.xkind == pxAmp and pfCpp in p.options.flags:
      getTok(p, result)
      let isConstB = skipConst(p)
      if isConstA or isConstB or p.lastConstType == result:
        discard "transform 'const Foo&' to just 'Foo'"
      else:
        let b = result
        result = newNodeP(nkVarTy, p)
        result.add(b)
    elif p.tok.xkind == pxAmpAmp and pfCpp in p.options.flags:
      getTok(p, result)
      skipConst(p)
      if pfIgnoreRvalueRefs notin p.options.flags:
        let b = result
        result = newNodeP(nkVarTy, p)
        result.add(b)
    else: break
  if a.kind == nkIdent and a.ident.s == "char":
    if i >= 2:
      result = newIdentNodeP("cstringArray", p)
      for j in 1..i-2: result = newPointerTy(p, result)
    elif i == 1: result = newIdentNodeP("cstring", p)
  elif a.kind == nkNilLit and i > 0:
    result = newIdentNodeP("pointer", p)
    for j in 1..i-1: result = newPointerTy(p, result)

proc newProcPragmas(p: Parser): PNode =
  result = newNodeP(nkPragma, p)
  if pfCDecl in p.options.flags:
    addSon(result, newIdentNodeP("cdecl", p))
  elif pfStdCall in p.options.flags:
    addSon(result, newIdentNodeP("stdcall", p))

proc addPragmas(father, pragmas: PNode) =
  if sonsLen(pragmas) > 0: addSon(father, pragmas)
  else: addSon(father, emptyNode)

proc addReturnType(params, rettyp: PNode): bool =
  if rettyp == nil: addSon(params, emptyNode)
  elif rettyp.kind != nkNilLit:
    addSon(params, rettyp)
    result = true
  else: addSon(params, emptyNode)

proc addDiscardable(origName: string; pragmas: PNode; p: Parser) =
  for prefix in p.options.discardablePrefixes:
    if origName.startsWith(prefix):
      addSon(pragmas, newIdentNodeP("discardable", p))

proc parseFormalParams(p: var Parser, params, pragmas: PNode)

proc parseTypeSuffix(p: var Parser, typ: PNode): PNode =
  result = typ
  case p.tok.xkind
  of pxBracketLe:
    getTok(p, result)
    skipConst(p) # POSIX contains: ``int [restrict]``
    if p.tok.xkind != pxBracketRi:
      var tmp = result
      var index = expression(p)
      # array type:
      result = newNodeP(nkBracketExpr, p)
      addSon(result, newIdentNodeP("array", p))
      addSon(result, index)
      eat(p, pxBracketRi, result)
      addSon(result, parseTypeSuffix(p, tmp))
    else:
      # pointer type:
      var tmp = result
      if pfRefs in p.options.flags:
        result = newNodeP(nkRefTy, p)
      else:
        result = newNodeP(nkPtrTy, p)
      eat(p, pxBracketRi, result)
      addSon(result, parseTypeSuffix(p, tmp))
  of pxParLe:
    # function pointer:
    var procType = newNodeP(nkProcTy, p)
    var pragmas = newProcPragmas(p)
    var params = newNodeP(nkFormalParams, p)
    discard addReturnType(params, result)
    parseFormalParams(p, params, pragmas)
    addSon(procType, params)
    addPragmas(procType, pragmas)
    result = parseTypeSuffix(p, procType)
  else: discard

proc typeDesc(p: var Parser): PNode = pointer(p, typeAtom(p))

proc abstractDeclarator(p: var Parser, a: PNode): PNode

proc directAbstractDeclarator(p: var Parser, a: PNode): PNode =
  if p.tok.xkind == pxParLe:
    getTok(p, a)
    if p.tok.xkind in {pxStar, pxAmp, pxAmpAmp}:
      result = abstractDeclarator(p, a)
      eat(p, pxParRi, result)
  result = parseTypeSuffix(p, a)

proc abstractDeclarator(p: var Parser, a: PNode): PNode =
  directAbstractDeclarator(p, pointer(p, a))

proc typeName(p: var Parser): PNode = abstractDeclarator(p, typeAtom(p))

proc parseField(p: var Parser, kind: TNodeKind): PNode =
  if p.tok.xkind == pxParLe:
    getTok(p, nil)
    while p.tok.xkind == pxStar: getTok(p, nil)
    result = parseField(p, kind)
    eat(p, pxParRi, result)
  else:
    expectIdent(p)
    if kind == nkRecList: result = fieldIdent(p.tok.s, p)
    else: result = mangledIdent(p.tok.s, p, skField)
    getTok(p, result)

proc structPragmas(p: Parser, name: PNode, origName: string): PNode =
  assert name.kind == nkIdent
  result = newNodeP(nkPragmaExpr, p)
  addSon(result, exportSym(p, name, origName))
  var pragmas = newNodeP(nkPragma, p)
  #addSon(pragmas, newIdentNodeP("pure", p), newIdentNodeP("final", p))
  if p.options.useHeader:
    addSon(pragmas,
      newIdentStrLitPair(p.options.importcLit, p.currentNamespace & origName, p),
      getHeaderPair(p))
  if p.options.inheritable.hasKey(origName):
    addSon(pragmas, newIdentNodeP("inheritable", p))
    addSon(pragmas, newIdentNodeP("pure", p))
  pragmas.add newIdentNodeP("bycopy", p)
  result.add pragmas

proc hashPosition(p: Parser): string =
  let lineInfo = parLineInfo(p)
  when declared(gConfig):
    let fileInfo = toFilename(gConfig, lineInfo.fileIndex).splitFile.name
  else:
    let fileInfo = toFilename(lineInfo.fileIndex).splitFile.name
  result = fileInfo & "_" & $lineInfo.line

proc parseInnerStruct(p: var Parser, stmtList: PNode,
                      isUnion: bool, name: string): PNode =
  if p.tok.xkind != pxCurlyLe:
    parMessage(p, errUser, "Expected '{' but found '" & $(p.tok[]) & "'")

  var structName: string
  if name == "":
    if isUnion: structName = "INNER_C_UNION_" & p.hashPosition
    else: structName = "INNER_C_STRUCT_" & p.hashPosition
  else:
    structName = name & "_" & p.hashPosition
  let typeSection = newNodeP(nkTypeSection, p)
  let newStruct = newNodeP(nkObjectTy, p)
  var pragmas = emptyNode
  if isUnion:
    pragmas = newNodeP(nkPragma, p)
    addSon(pragmas, newIdentNodeP("union", p))
  addSon(newStruct, pragmas, emptyNode) # no inheritance
  result = newNodeP(nkIdent, p)
  result.ident = getIdent(structName)
  let struct = parseStructBody(p, stmtList, isUnion)
  let defName = newNodeP(nkIdent, p)
  defName.ident = getIdent(structName)
  addSon(newStruct, struct)
  addTypeDef(typeSection, structPragmas(p, defName, "no_name"), newStruct,
             emptyNode)
  addSon(stmtList, typeSection)

proc parseStructBody(p: var Parser, stmtList: PNode, isUnion: bool,
                     kind: TNodeKind = nkRecList): PNode =
  result = newNodeP(kind, p)
  eat(p, pxCurlyLe, result)
  while p.tok.xkind notin {pxEof, pxCurlyRi}:
    skipConst(p)
    var baseTyp: PNode
    if p.tok.xkind == pxSymbol and (p.tok.s == "struct" or p.tok.s == "union"):
      let gotUnion = if p.tok.s == "union": true   else: false
      saveContext(p)
      getTok(p, nil)
      let prev = p
      getTok(p, nil)
      if prev.tok.xkind == pxSymbol and p.tok.xkind != pxCurlyLe:
        backtrackContext(p)
        baseTyp = typeAtom(p)
      else:
        backtrackContext(p)
        getTok(p)
        var name = ""
        if p.tok.xkind == pxSymbol:
          name = p.tok.s
          getTok(p)
        baseTyp = parseInnerStruct(p, stmtList, gotUnion, name)
        if p.tok.xkind == pxSemiColon:
          let def = newNodeP(nkIdentDefs, p)
          var t = pointer(p, baseTyp)
          let i = fieldIdent("ano_" & p.hashPosition, p)
          t = parseTypeSuffix(p, t)
          addSon(def, i, t, emptyNode)
          addSon(result, def)
          getTok(p, nil)
          continue
    elif p.tok.xkind == pxDirective or p.tok.xkind == pxDirectiveParLe:
      var define = parseDir(p, statement)
      addSon(result, define)
      baseTyp = typeAtom(p)
    else:
      baseTyp = typeAtom(p)

    while true:
      var def = newNodeP(nkIdentDefs, p)
      var t = pointer(p, baseTyp)
      var i = parseField(p, kind)
      t = parseTypeSuffix(p, t)
      if p.tok.xkind == pxColon:
        getTok(p)
        var bits = p.tok.iNumber
        eat(p, pxIntLit)
        var pragma = newNodeP(nkPragma, p)
        var bitsize = newNodeP(nkExprColonExpr, p)
        addSon(bitsize, newIdentNodeP("bitsize", p))
        addSon(bitsize, newIntNodeP(nkIntLit, bits, p))
        addSon(pragma, bitsize)
        var pragmaExpr = newNodeP(nkPragmaExpr, p)
        addSon(pragmaExpr, i)
        addSon(pragmaExpr, pragma)
        i = pragmaExpr
      addSon(def, i, t, emptyNode)
      addSon(result, def)
      if p.tok.xkind != pxComma: break
      getTok(p, def)
    eat(p, pxSemicolon, lastSon(result))
  eat(p, pxCurlyRi, result)

proc enumPragmas(p: Parser, name: PNode; origName: string): PNode =
  result = newNodeP(nkPragmaExpr, p)
  addSon(result, name)
  var pragmas = newNodeP(nkPragma, p)
  if p.options.dynlibSym.len > 0 or p.options.useHeader:
    var e = newNodeP(nkExprColonExpr, p)
    # HACK: sizeof(cint) should be constructed as AST
    addSon(e, newIdentNodeP("size", p), newIdentNodeP("sizeof(cint)", p))
    addSon(pragmas, e)
  if p.options.inheritable.hasKey(origName):
    addSon(pragmas, newIdentNodeP("pure", p))
  if pfCpp in p.options.flags and p.options.useHeader:
    let importName =
          if p.currentClassOrig.len > 0:
            p.currentNamespace & p.currentClassOrig & "::" & origName
          else:
            p.currentNamespace & origName
    addSon(pragmas, newIdentStrLitPair("importcpp", importName, p))
    addSon(pragmas, getHeaderPair(p))
  if pragmas.len > 0:
    addSon(result, pragmas)
  else:
    result = name


proc skipInheritKeyw(p: var Parser) =
  if p.tok.xkind == pxSymbol and (p.tok.s == "private" or
                                  p.tok.s == "protected" or
                                  p.tok.s == "public"):
    getTok(p)

proc parseInheritance(p: var Parser; result: PNode) =
  if p.tok.xkind == pxColon:
    getTok(p, result)
    skipInheritKeyw(p)
    var baseTyp = typeAtom(p)
    var inh = newNodeP(nkOfInherit, p)
    inh.add(baseTyp)
    if p.tok.xkind == pxComma:
      parMessage(p, warnUser, "multiple inheritance is not supported")
      while p.tok.xkind == pxComma:
        getTok(p)
        skipInheritKeyw(p)
        discard typeAtom(p)
    result.sons[0] = inh

proc parseStruct(p: var Parser, stmtList: PNode, isUnion: bool): PNode =
  result = newNodeP(nkObjectTy, p)
  var pragmas = emptyNode
  if isUnion:
    pragmas = newNodeP(nkPragma, p)
    addSon(pragmas, newIdentNodeP("union", p))
  addSon(result, pragmas, emptyNode) # no inheritance
  parseInheritance(p, result)
  if p.tok.xkind == pxCurlyLe:
    addSon(result, parseStructBody(p, stmtList, isUnion))
  else:
    addSon(result, newNodeP(nkRecList, p))

proc declarator(p: var Parser, a: PNode, ident: ptr PNode): PNode

proc directDeclarator(p: var Parser, a: PNode, ident: ptr PNode): PNode =
  case p.tok.xkind
  of pxSymbol:
    ident[] = skipIdent(p, skParam)
  of pxParLe:
    getTok(p, a)
    if p.tok.xkind in {pxStar, pxAmp, pxAmpAmp, pxSymbol}:
      result = declarator(p, a, ident)
      eat(p, pxParRi, result)
  else:
    discard
  return parseTypeSuffix(p, a)

proc declarator(p: var Parser, a: PNode, ident: ptr PNode): PNode =
  directDeclarator(p, pointer(p, a), ident)

# parameter-declaration
#   declaration-specifiers declarator
#   declaration-specifiers asbtract-declarator(opt)
proc parseParam(p: var Parser, params: PNode) =
  var typ = typeDesc(p)
  # support for ``(void)`` parameter list:
  if typ.kind == nkNilLit and p.tok.xkind == pxParRi: return
  var name: PNode
  typ = declarator(p, typ, addr name)
  if name == nil:
    var idx = sonsLen(params)
    name = newIdentNodeP(p.options.paramPrefix & $idx, p)
  var x = newNodeP(nkIdentDefs, p)
  addSon(x, name, typ)
  if p.tok.xkind == pxAsgn:
    # for the wxWidgets wrapper we need to transform 'auto x = foo' into
    # 'x = foo' cause 'x: auto = foo' is not really supported by Nim yet...
    if typ.kind == nkIdent and typ.ident.s == "auto":
      x.sons[^1] = emptyNode
    # we support default parameters for C++:
    getTok(p, x)
    addSon(x, assignmentExpression(p))
  else:
    addSon(x, emptyNode)
  addSon(params, x)

proc parseFormalParams(p: var Parser, params, pragmas: PNode) =
  eat(p, pxParLe, params)
  while p.tok.xkind notin {pxEof, pxParRi}:
    if p.tok.xkind == pxDotDotDot:
      addSon(pragmas, newIdentNodeP("varargs", p))
      getTok(p, pragmas)
      break
    parseParam(p, params)
    if p.tok.xkind != pxComma: break
    getTok(p, params)
  eat(p, pxParRi, params)

proc parseCallConv(p: var Parser, pragmas: PNode) =
  while p.tok.xkind == pxSymbol:
    case p.tok.s
    of "inline", "__inline":
      if pfCpp in p.options.flags and pfKeepbodies notin p.options.flags:
        discard
      else:
        addSon(pragmas, newIdentNodeP("inline", p))
    of "__cdecl": addSon(pragmas, newIdentNodeP("cdecl", p))
    of "__stdcall": addSon(pragmas, newIdentNodeP("stdcall", p))
    of "__syscall": addSon(pragmas, newIdentNodeP("syscall", p))
    of "__fastcall": addSon(pragmas, newIdentNodeP("fastcall", p))
    of "__safecall": addSon(pragmas, newIdentNodeP("safecall", p))
    else: break
    getTok(p, nil)

proc parseFunctionPointerDecl(p: var Parser, rettyp: PNode): PNode =
  var procType = newNodeP(nkProcTy, p)
  var pragmas = newProcPragmas(p)
  var params = newNodeP(nkFormalParams, p)
  eat(p, pxParLe, params)
  discard addReturnType(params, rettyp)
  parseCallConv(p, pragmas)

  if pfCpp in p.options.flags and p.tok.xkind == pxSymbol:
    getTok(p)
    eat(p, pxScope)
    addSon(pragmas, newIdentNodeP("memberfuncptr", p))

  if p.tok.xkind == pxStar: getTok(p, params)
  #else: parMessage(p, errGenerated, "expected '*'")
  if p.inTypeDef > 0: markTypeIdent(p, nil)
  var name = skipIdentExport(p, if p.inTypeDef > 0: skType else: skVar)
  eat(p, pxParRi, name)
  parseFormalParams(p, params, pragmas)
  addSon(procType, params)
  addPragmas(procType, pragmas)

  if p.inTypeDef == 0:
    result = newNodeP(nkVarSection, p)
    var def = newNodeP(nkIdentDefs, p)
    addSon(def, name, procType, emptyNode)
    addSon(result, def)
  else:
    result = newNodeP(nkTypeDef, p)
    addSon(result, name, emptyNode, procType)
  assert result != nil

proc addTypeDef(section, name, t, genericParams: PNode) =
  var def = newNodeI(nkTypeDef, name.info)
  addSon(def, name, genericParams, t)
  addSon(section, def)

proc otherTypeDef(p: var Parser, section, typ: PNode) =
  var name: PNode
  var t = typ
  if p.tok.xkind in {pxStar, pxAmp, pxAmpAmp}:
    t = pointer(p, t)
  if p.tok.xkind == pxParLe:
    # function pointer: typedef typ (*name)();
    var x = parseFunctionPointerDecl(p, t)
    name = x[0]
    t = x[2]
  else:
    # typedef typ name;
    if t.kind == nkNilLit: t = newIdentNodeP("void", p)
    markTypeIdent(p, t)
    name = skipIdentExport(p, skType)
  t = parseTypeSuffix(p, t)
  addTypeDef(section, name, t, emptyNode)

proc parseTrailingDefinedTypes(p: var Parser, section, typ: PNode) =
  while p.tok.xkind == pxComma:
    getTok(p, nil)
    var newTyp = pointer(p, typ)
    markTypeIdent(p, newTyp)
    var newName = skipIdentExport(p, skType)
    newTyp = parseTypeSuffix(p, newTyp)
    addTypeDef(section, newName, newTyp, emptyNode)

proc createConst(name, typ, val: PNode, p: Parser): PNode =
  result = newNodeP(nkConstDef, p)
  addSon(result, name, typ, val)

proc exprToNumber(n: PNode): tuple[succ: bool, val: BiggestInt] =
  result = (false, 0.BiggestInt)
  case n.kind:
  of nkPrefix:
    # Check for negative/positive numbers  -3  or  +6
    if n.sons.len == 2 and n.sons[0].kind == nkIdent and n.sons[1].kind == nkIntLit:
      let pre = n.sons[0]
      let num = n.sons[1]
      if pre.ident.s == "-": result = (true, -num.intVal)
      elif pre.ident.s == "+": result = (true, num.intVal)
  else: discard

when not declared(sequtils.any):
  template any(x, cond: untyped): untyped =
    var result = false
    for it {.inject.} in x:
      if cond: result = true; break
    result

proc getEnumIdent(n: PNode): PNode =
  if n.kind == nkEnumFieldDef: result = n[0]
  else: result = n
  assert result.kind == nkIdent

proc enumFields(p: var Parser, constList: PNode): PNode =
  type EnumFieldKind = enum isNormal, isNumber, isAlias
  result = newNodeP(nkEnumTy, p)
  addSon(result, emptyNode) # enum does not inherit from anything
  var i: BiggestInt = 0
  var field: tuple[id: BiggestInt, kind: EnumFieldKind, node, value: PNode]
  var fields = newSeq[type(field)]()
  while true:
    var e = skipIdent(p, skEnumField)
    if p.tok.xkind == pxAsgn:
      getTok(p, e)
      var c = constantExpression(p)
      var a = e
      e = newNodeP(nkEnumFieldDef, p)
      addSon(e, a, c)
      skipCom(p, e)
      field.value = c
      if c.kind == nkIntLit:
        i = c.intVal
        field.kind = isNumber
      else:
        var (success, number) = exprToNumber(c)
        if success:
          i = number
          field.kind = isNumber
        elif any(fields,
            c.kind == nkIdent and it.node.getEnumIdent.ident.s == c.ident.s):
          field.kind = isAlias
        else:
          field.kind = isNormal
    else:
      inc(i)
      field.kind = isNumber
    field.id = i
    field.node = e
    fields.add(field)
    if p.tok.xkind != pxComma: break
    getTok(p, e)
    # allow trailing comma:
    if p.tok.xkind == pxCurlyRi: break
  fields.sort do (x, y: type(field)) -> int:
    cmp(x.id, y.id)
  var lastId: BiggestInt
  var lastIdent: PNode
  const outofOrder = "failed to sort enum fields"
  for count, f in fields:
    case f.kind
    of isNormal:
      addSon(result, f.node)
    of isNumber:
      if f.id == lastId and count > 0:
        var currentIdent: PNode
        case f.node.kind:
        of nkEnumFieldDef:
          if f.node.sons.len > 0 and f.node.sons[0].kind == nkIdent:
            currentIdent = f.node.sons[0]
          else: parMessage(p, errGenerated, outofOrder)
        of nkIdent: currentIdent = f.node
        else: parMessage(p, errGenerated, outofOrder)
        var constant = createConst(currentIdent, emptyNode, lastIdent, p)
        constList.addSon(constant)
      else:
        addSon(result, f.node)
        lastId = f.id
        case f.node.kind:
        of nkEnumFieldDef:
          if f.node.sons.len > 0 and f.node.sons[0].kind == nkIdent:
            lastIdent = f.node.sons[0]
          else: parMessage(p, errGenerated, outofOrder)
        of nkIdent: lastIdent = f.node
        else: parMessage(p, errGenerated, outofOrder)
    of isAlias:
      var constant = createConst(f.node.getEnumIdent, emptyNode, f.value, p)
      constList.addSon(constant)


proc parseTypedefStruct(p: var Parser, result, stmtList: PNode, isUnion: bool) =
  getTok(p, result)
  if p.tok.xkind == pxCurlyLe:
    var t = parseStruct(p, stmtList, isUnion)
    var origName = p.tok.s
    markTypeIdent(p, nil)
    var name = skipIdent(p, skType)
    addTypeDef(result, structPragmas(p, name, origName), t, emptyNode)
    parseTrailingDefinedTypes(p, result, name)
  elif p.tok.xkind == pxSymbol:
    # name to be defined or type "struct a", we don't know yet:
    markTypeIdent(p, nil)
    var origName = p.tok.s
    var nameOrType = skipIdent(p, skVar)
    case p.tok.xkind
    of pxCurlyLe:
      var t = parseStruct(p, stmtList, isUnion)
      if p.tok.xkind == pxSymbol:
        # typedef struct tagABC {} abc, *pabc;
        # --> abc is a better type name than tagABC!
        markTypeIdent(p, nil)
        var origName = p.tok.s
        var name = skipIdent(p, skType)
        addTypeDef(result, structPragmas(p, name, origName), t, emptyNode)
        parseTrailingDefinedTypes(p, result, name)
      else:
        addTypeDef(result, structPragmas(p, nameOrType, origName), t,
                   emptyNode)
    of pxSymbol:
      # typedef struct a a?
      if mangleName(p.tok.s, p, skType) == nameOrType.ident.s:
        # ignore the declaration:
        if pfStructStruct in p.options.flags:
          # XXX to implement
          getTok(p, nil)
        else:
          getTok(p, nil)
      else:
        # typedef struct a b; or typedef struct a b[45];
        otherTypeDef(p, result, nameOrType)
    else:
      otherTypeDef(p, result, nameOrType)
  else:
    expectIdent(p)

proc parseTypedefEnum(p: var Parser, result, constSection: PNode) =
  getTok(p, result)
  if p.tok.xkind == pxCurlyLe:
    getTok(p, result)
    var t = enumFields(p, constSection)
    eat(p, pxCurlyRi, t)
    var origName = p.tok.s
    markTypeIdent(p, nil)
    var name = skipIdent(p, skType)
    addTypeDef(result, enumPragmas(p, exportSym(p, name, origName), origName),
               t, emptyNode)
    parseTrailingDefinedTypes(p, result, name)
  elif p.tok.xkind == pxSymbol:
    # name to be defined or type "enum a", we don't know yet:
    markTypeIdent(p, nil)
    var origName = p.tok.s
    var nameOrType = skipIdent(p, skType)
    case p.tok.xkind
    of pxCurlyLe:
      getTok(p, result)
      var t = enumFields(p, constSection)
      eat(p, pxCurlyRi, t)
      if p.tok.xkind == pxSymbol:
        # typedef enum tagABC {} abc, *pabc;
        # --> abc is a better type name than tagABC!
        markTypeIdent(p, nil)
        var origName = p.tok.s
        var name = skipIdent(p, skType)
        addTypeDef(result, enumPragmas(p, exportSym(p, name, origName), origName),
                   t, emptyNode)
        parseTrailingDefinedTypes(p, result, name)
      else:
        addTypeDef(result,
                   enumPragmas(p, exportSym(p, nameOrType, origName), origName),
                   t, emptyNode)
    of pxSymbol:
      # typedef enum a a?
      if mangleName(p.tok.s, p, skType) == nameOrType.ident.s:
        # ignore the declaration:
        getTok(p, nil)
      else:
        # typedef enum a b; or typedef enum a b[45];
        otherTypeDef(p, result, nameOrType)
    else:
      otherTypeDef(p, result, nameOrType)
  else:
    expectIdent(p)

proc parseTypeDef(p: var Parser): PNode =
  result = newNodeP(nkStmtList, p)
  var typeSection = newNodeP(nkTypeSection, p)
  var afterStatements = newNodeP(nkStmtList, p)
  while p.tok.xkind == pxSymbol and p.tok.s == "typedef":
    getTok(p, typeSection)
    inc(p.inTypeDef)
    expectIdent(p)
    case p.tok.s
    of "struct": parseTypedefStruct(p, typeSection, result, isUnion=false)
    of "union": parseTypedefStruct(p, typeSection, result, isUnion=true)
    of "enum":
      var constSection = newNodeP(nkConstSection, p)
      parseTypedefEnum(p, typeSection, constSection)
      addSon(afterStatements, constSection)
    of "class":
      if pfCpp in p.options.flags:
        parseTypedefStruct(p, typeSection, result, isUnion=false)
      else:
        var t = typeAtom(p)
        otherTypeDef(p, typeSection, t)
    else:
      var t = typeAtom(p)
      otherTypeDef(p, typeSection, t)
    eat(p, pxSemicolon)
    dec(p.inTypeDef)

  addSon(result, typeSection)
  for s in afterStatements:
    addSon(result, s)

proc skipDeclarationSpecifiers(p: var Parser) =
  while p.tok.xkind == pxSymbol:
    case p.tok.s
    of "extern", "static", "auto", "register", "const", "constexpr", "volatile":
      getTok(p, nil)
    of "mutable":
      if pfCpp in p.options.flags: getTok(p, nil)
      else: break
    else: break

proc skipThrowSpecifier(p: var Parser) =
  if p.tok.xkind == pxSymbol and p.tok.s == "throw":
    getTok(p)
    var pms = newNodeP(nkFormalParams, p)
    var pgms = newNodeP(nkPragma, p)
    parseFormalParams(p, pms, pgms) #ignore

proc parseInitializer(p: var Parser): PNode =
  if p.tok.xkind == pxCurlyLe:
    result = newNodeP(nkBracket, p)
    getTok(p, result)
    while p.tok.xkind notin {pxEof, pxCurlyRi}:
      addSon(result, parseInitializer(p))
      opt(p, pxComma, nil)
    eat(p, pxCurlyRi, result)
  else:
    result = assignmentExpression(p)

proc addInitializer(p: var Parser, def: PNode) =
  if p.tok.xkind == pxAsgn:
    getTok(p, def)
    let initVal = parseInitializer(p)
    if p.options.dynlibSym.len > 0 or p.options.useHeader:
      addSon(def, emptyNode)
    else:
      addSon(def, initVal)
  else:
    addSon(def, emptyNode)

proc parseVarDecl(p: var Parser, baseTyp, typ: PNode,
                  origName: string): PNode =
  result = newNodeP(nkVarSection, p)
  var def = newNodeP(nkIdentDefs, p)
  addSon(def, varIdent(origName, p))
  addSon(def, parseTypeSuffix(p, typ))
  addInitializer(p, def)
  addSon(result, def)

  while p.tok.xkind == pxComma:
    getTok(p, def)
    var t = pointer(p, baseTyp)
    expectIdent(p)
    def = newNodeP(nkIdentDefs, p)
    addSon(def, varIdent(p.tok.s, p))
    getTok(p, def)
    addSon(def, parseTypeSuffix(p, t))
    addInitializer(p, def)
    addSon(result, def)

  if p.options.useHeader and p.options.flags.contains(pfCpp):
    var unmatched_braces = 0
    while true: # skip c++11 list initializer
      if p.tok.xkind == pxCurlyLe:
        eat(p, pxCurlyLe)
        inc unmatched_braces
        continue
      elif p.tok.xkind == pxCurlyRi:
        eat(p, pxCurlyRi)
        dec unmatched_braces
        continue
      if unmatched_braces == 0:
        break
      # consume initalizer list contents
      getTok(p, nil)
  eat(p, pxSemicolon)

proc parseOperator(p: var Parser, origName: var string): bool =
  getTok(p) # skip 'operator' keyword
  case p.tok.xkind
  of pxAmp..pxArrowStar, pxComma:
    # ordinary operator symbol:
    origName.add(tokKindToStr(p.tok.xkind))
    getTok(p)
  of pxSymbol:
    if p.tok.s == "new" or p.tok.s == "delete":
      origName.add(p.tok.s)
      getTok(p)
      if p.tok.xkind == pxBracketLe:
        getTok(p)
        eat(p, pxBracketRi)
        origName.add("[]")
    else:
      # type converter
      let x = typeAtom(p)
      if x.kind == nkIdent:
        origName.add(x.ident.s)
      else:
        parMessage(p, errGenerated, "operator symbol expected")
      result = true
  of pxParLe:
    getTok(p)
    eat(p, pxParRi)
    origName.add("()")
  of pxBracketLe:
    getTok(p)
    eat(p, pxBracketRi)
    origName.add("[]")
  else:
    parMessage(p, errGenerated, "operator symbol expected")

when false:
  proc declarationName(p: var Parser): string =
    while p.tok.xkind == pxScope and pfCpp in p.options.flags:
      getTok(p) # skip "::"
      expectIdent(p)
      result.add("::")
      result.add(p.tok.s)
      getTok(p)

proc parseMethod(p: var Parser, origName: string, rettyp, pragmas: PNode,
                 isStatic, isOperator, hasPointlessPar: bool;
                 genericParams, genericParamsThis: PNode): PNode

proc declaration(p: var Parser; genericParams: PNode = emptyNode): PNode =
  result = newNodeP(nkProcDef, p)
  var pragmas = newNodeP(nkPragma, p)

  skipDeclarationSpecifiers(p)
  parseCallConv(p, pragmas)
  skipDeclarationSpecifiers(p)
  expectIdent(p)
  var baseTyp = typeAtom(p)
  var rettyp = pointer(p, baseTyp)
  skipDeclarationSpecifiers(p)
  parseCallConv(p, pragmas)
  skipDeclarationSpecifiers(p)

  if p.tok.xkind == pxParLe:
    # Function pointer declaration: This is of course only a heuristic, but the
    # best we can do here.
    result = parseFunctionPointerDecl(p, rettyp)
    eat(p, pxSemicolon)
    return

  expectIdent(p)
  var origName = p.tok.s
  if pfCpp in p.options.flags and p.tok.s == "operator":
    origName = ""
    var isConverter = parseOperator(p, origName)
    result = parseMethod(p, origName, rettyp, pragmas, true, true,
                         false, emptyNode, emptyNode)
    if isConverter: result.kind = nkConverterDef
    # don't add trivial operators that Nim ends up using anyway:
    if origName in ["=", "!=", ">", ">="]:
      result = emptyNode
    return
  else:
    getTok(p) # skip identifier

  case p.tok.xkind
  of pxParLe:
    # really a function!
    var name = mangledIdent(origName, p, skProc)
    var params = newNodeP(nkFormalParams, p)
    if addReturnType(params, rettyp):
      addDiscardable(origName, pragmas, p)
    parseFormalParams(p, params, pragmas)
    if pfCpp in p.options.flags and p.tok.xkind == pxSymbol and
        p.tok.s == "const":
      addSon(pragmas, newIdentNodeP("noSideEffect", p))
      getTok(p)
    if pfCDecl in p.options.flags:
      addSon(pragmas, newIdentNodeP("cdecl", p))
    elif pfStdcall in p.options.flags:
      addSon(pragmas, newIdentNodeP("stdcall", p))
    # no pattern, no exceptions:
    addSon(result, exportSym(p, name, origName), emptyNode, genericParams)
    addSon(result, params, pragmas, emptyNode) # no exceptions
    skipThrowSpecifier(p)
    case p.tok.xkind
    of pxSemicolon:
      getTok(p)
      addSon(result, emptyNode) # no body
      if p.scopeCounter == 0:
        if pfCpp in p.options.flags:
          doImportCpp(p.currentNamespace & origName & "(@)", pragmas, p)
        else:
          doImport(origName, pragmas, p)
    of pxCurlyLe:
      if {pfCpp, pfKeepBodies} * p.options.flags == {pfCpp}:
        discard compoundStatement(p)
        addSon(result, newNodeP(nkDiscardStmt, p))
        addSon(result.lastSon, emptyNode)
      else:
        addSon(result, compoundStatement(p))
    else:
      parMessage(p, errGenerated, "expected ';'")
    if sonsLen(result.sons[pragmasPos]) == 0:
      result.sons[pragmasPos] = emptyNode
  of pxScope:
    # outlined C++ method:
    getTok(p)
    expectIdent(p)
    var origFnName = p.tok.s
    getTok(p)

    let isStatic = not p.options.classes.hasKey(origName)
    var oldClass: PNode
    var oldClassOrig: string
    if not isStatic:
      oldClass = p.currentClass
      oldClassOrig = p.currentClassOrig
      p.currentClassOrig = origName
      p.currentClass = mangledIdent(p.currentClassOrig, p, skType)

    result = parseMethod(p, origFnName, rettyp, pragmas,
                         isStatic, false, false, emptyNode, emptyNode)
    if not isStatic:
      p.currentClass = oldClass
      p.currentClassOrig = oldClassOrig

  else:
    result = parseVarDecl(p, baseTyp, rettyp, origName)
  assert result != nil

proc enumSpecifier(p: var Parser): PNode =
  saveContext(p)
  getTok(p, nil) # skip "enum"
  case p.tok.xkind
  of pxCurlyLe:
    closeContext(p)
    # make a const section out of it:
    result = newNodeP(nkConstSection, p)
    getTok(p, result)
    var i = 0
    var hasUnknown = false
    while true:
      var name = skipIdentExport(p, skEnumField)
      var val: PNode
      if p.tok.xkind == pxAsgn:
        getTok(p, name)
        val = constantExpression(p)
        if val.kind == nkIntLit:
          i = int(val.intVal)+1
          hasUnknown = false
        else:
          hasUnknown = true
      else:
        if hasUnknown:
          parMessage(p, warnUser, "computed const value may be wrong: " &
            name.renderTree)
        val = newIntNodeP(nkIntLit, i, p)
        inc(i)
      var c = createConst(name, emptyNode, val, p)
      addSon(result, c)
      if p.tok.xkind != pxComma: break
      getTok(p, c)
      # allow trailing comma:
      if p.tok.xkind == pxCurlyRi: break
    eat(p, pxCurlyRi, result)
    eat(p, pxSemicolon)
  of pxSymbol:
    var origName = p.tok.s
    markTypeIdent(p, nil)
    result = skipIdent(p, skType)
    case p.tok.xkind
    of pxCurlyLe:
      closeContext(p)
      var name = result
      # create a type section containing the enum
      result = newNodeP(nkStmtList, p)
      var tSection = newNodeP(nkTypeSection, p)
      var t = newNodeP(nkTypeDef, p)
      getTok(p, t)
      var constSection = newNodeP(nkConstSection, p)
      var e = enumFields(p, constSection)
      addSon(t, enumPragmas(p, exportSym(p, name, origName), origName),
             emptyNode, e)
      addSon(tSection, t)
      addSon(result, tSection)
      addSon(result, constSection)
      eat(p, pxCurlyRi, result)
      eat(p, pxSemicolon)
    of pxSemicolon:
      # just ignore ``enum X;`` for now.
      closeContext(p)
      getTok(p, nil)
    else:
      backtrackContext(p)
      result = declaration(p)
  else:
    closeContext(p)
    parMessage(p, errGenerated, "expected '{'")
    result = emptyNode

# Expressions

proc setBaseFlags(n: PNode, base: NumericalBase) =
  case base
  of base10: discard
  of base2: incl(n.flags, nfBase2)
  of base8: incl(n.flags, nfBase8)
  of base16: incl(n.flags, nfBase16)

proc startExpression(p: var Parser, tok: Token): PNode =
  case tok.xkind:
  of pxSymbol:
    if tok.s == "NULL":
      result = newNodeP(nkNilLit, p)
    elif tok.s == "sizeof":
      result = newNodeP(nkCall, p)
      addSon(result, newIdentNodeP("sizeof", p))
      saveContext(p)
      try:
        addSon(result, expression(p, 139))
        closeContext(p)
      except ERetryParsing:
        backtrackContext(p)
        eat(p, pxParLe)
        addSon(result, typeName(p))
        eat(p, pxParRi)
    elif (tok.s == "new" or tok.s == "delete") and pfCpp in p.options.flags:
      var opr = tok.s
      result = newNodeP(nkCall, p)
      if p.tok.xkind == pxBracketLe:
        getTok(p)
        eat(p, pxBracketRi)
        opr.add("Array")
      addSon(result, newIdentNodeP(opr, p))
      if p.tok.xkind == pxParLe:
        getTok(p, result)
        addSon(result, typeDesc(p))
        eat(p, pxParRi, result)
      else:
        addSon(result, expression(p, 139))
    else:
      let kind = if p.inAngleBracket > 0: skType else: skProc
      if kind == skProc and p.options.classes.hasKey(tok.s):
        result = mangledIdent(p.options.constructor & tok.s, p, kind)
      else:
        result = mangledIdent(tok.s, p, kind)
      result = optScope(p, result, kind)
      result = optAngle(p, result)
  of pxIntLit:
    result = newIntNodeP(nkIntLit, tok.iNumber, p)
    setBaseFlags(result, tok.base)
  of pxInt64Lit:
    result = newIntNodeP(nkInt64Lit, tok.iNumber, p)
    setBaseFlags(result, tok.base)
  of pxFloatLit:
    result = newFloatNodeP(nkFloatLit, tok.fNumber, p)
    setBaseFlags(result, tok.base)
  of pxStrLit:
    result = newStrNodeP(nkStrLit, tok.s, p)
    while p.tok.xkind == pxStrLit:
      add(result.strVal, p.tok.s)
      getTok(p, result)
  of pxCharLit:
    result = newIntNodeP(nkCharLit, ord(tok.s[0]), p)
  of pxParLe:
    try:
      saveContext(p)
      result = newNodeP(nkPar, p)
      addSon(result, expression(p, 0))
      if p.tok.xkind != pxParRi:
        raise newException(ERetryParsing, "expected a ')'")
      getTok(p, result)
      if p.tok.xkind in {pxSymbol, pxIntLit, pxFloatLit, pxStrLit, pxCharLit}:
        raise newException(ERetryParsing, "expected a non literal token")
      closeContext(p)
    except ERetryParsing:
      backtrackContext(p)
      result = newNodeP(nkCast, p)
      addSon(result, typeName(p))
      eat(p, pxParRi, result)
      addSon(result, expression(p, 139))
  of pxPlusPlus:
    result = newNodeP(nkCall, p)
    addSon(result, newIdentNodeP("inc", p))
    addSon(result, expression(p, 139))
  of pxMinusMinus:
    result = newNodeP(nkCall, p)
    addSon(result, newIdentNodeP("dec", p))
    addSon(result, expression(p, 139))
  of pxAmp:
    result = newNodeP(nkAddr, p)
    addSon(result, expression(p, 139))
  of pxStar:
    result = newNodeP(nkBracketExpr, p)
    addSon(result, expression(p, 139))
  of pxPlus:
    result = newNodeP(nkPrefix, p)
    addSon(result, newIdentNodeP("+", p))
    addSon(result, expression(p, 139))
  of pxMinus:
    result = newNodeP(nkPrefix, p)
    addSon(result, newIdentNodeP("-", p))
    addSon(result, expression(p, 139))
  of pxTilde:
    result = newNodeP(nkPrefix, p)
    addSon(result, newIdentNodeP("not", p))
    addSon(result, expression(p, 139))
  of pxNot:
    result = newNodeP(nkPrefix, p)
    addSon(result, newIdentNodeP("not", p))
    addSon(result, expression(p, 139))
  of pxVerbatim:
    result = newIdentNodeP(tok.s, p)
  else:
    # probably from a failed sub expression attempt, try a type cast
    raise newException(ERetryParsing, "did not expect " & $tok)

proc leftBindingPower(p: var Parser, tok: ref Token): int =
  case tok.xkind
  of pxComma:
    return 10
    # throw == 20
  of pxAsgn, pxPlusAsgn, pxMinusAsgn, pxStarAsgn, pxSlashAsgn, pxModAsgn,
     pxShlAsgn, pxShrAsgn, pxAmpAsgn, pxHatAsgn, pxBarAsgn:
    return 30
  of pxConditional:
    return 40
  of pxBarBar:
    return 50
  of pxAmpAmp:
    return 60
  of pxBar:
    return 70
  of pxHat:
    return 80
  of pxAmp:
    return 90
  of pxEquals, pxNeq:
    return 100
  of pxLt, pxLe, pxGt, pxGe:
    return 110
  of pxShl, pxShr:
    return 120
  of pxPlus, pxMinus:
    return 130
  of pxStar, pxSlash, pxMod:
    return 140
    # .* ->* == 150
  of pxPlusPlus, pxMinusMinus, pxParLe, pxDot, pxArrow, pxArrowStar,
     pxBracketLe:
    return 160
    # :: == 170
  else:
    return 0

proc buildStmtList(a: PNode): PNode

proc leftExpression(p: var Parser, tok: Token, left: PNode): PNode =
  case tok.xkind
  of pxComma: # 10
    # not supported as an expression, turns into a statement list
    result = buildStmtList(left)
    addSon(result, expression(p, 0))
    # throw == 20
  of pxAsgn: # 30
    result = newNodeP(nkAsgn, p)
    addSon(result, left, expression(p, 29))
  of pxPlusAsgn: # 30
    result = newNodeP(nkCall, p)
    addSon(result, newIdentNodeP(getIdent("inc"), p), left, expression(p, 29))
  of pxMinusAsgn: # 30
    result = newNodeP(nkCall, p)
    addSon(result, newIdentNodeP(getIdent("dec"), p), left, expression(p, 29))
  of pxStarAsgn: # 30
    result = newNodeP(nkAsgn, p)
    var right = expression(p, 29)
    addSon(result, left, newBinary("*", copyTree(left), right, p))
  of pxSlashAsgn: # 30
    result = newNodeP(nkAsgn, p)
    var right = expression(p, 29)
    addSon(result, left, newBinary("/", copyTree(left), right, p))
  of pxModAsgn: # 30
    result = newNodeP(nkAsgn, p)
    var right = expression(p, 29)
    addSon(result, left, newBinary("mod", copyTree(left), right, p))
  of pxShlAsgn: # 30
    result = newNodeP(nkAsgn, p)
    var right = expression(p, 29)
    addSon(result, left, newBinary("shl", copyTree(left), right, p))
  of pxShrAsgn: # 30
    result = newNodeP(nkAsgn, p)
    var right = expression(p, 29)
    addSon(result, left, newBinary("shr", copyTree(left), right, p))
  of pxAmpAsgn: # 30
    result = newNodeP(nkAsgn, p)
    var right = expression(p, 29)
    addSon(result, left, newBinary("and", copyTree(left), right, p))
  of pxHatAsgn: # 30
    result = newNodeP(nkAsgn, p)
    var right = expression(p, 29)
    addSon(result, left, newBinary("xor", copyTree(left), right, p))
  of pxBarAsgn: # 30
    result = newNodeP(nkAsgn, p)
    var right = expression(p, 29)
    addSon(result, left, newBinary("or", copyTree(left), right, p))
  of pxConditional: # 40
    var a = expression(p, 0)
    eat(p, pxColon, a)
    var b = expression(p, 39)
    result = newNodeP(nkIfExpr, p)
    var branch = newNodeP(nkElifExpr, p)
    addSon(branch, left, a)
    addSon(result, branch)
    branch = newNodeP(nkElseExpr, p)
    addSon(branch, b)
    addSon(result, branch)
  of pxBarBar: # 50
    result = newBinary("or", left, expression(p, 50), p)
  of pxAmpAmp: # 60
    result = newBinary("and", left, expression(p, 60), p)
  of pxBar: # 70
    result = newBinary("or", left, expression(p, 70), p)
  of pxHat: # 80
    result = newBinary("xor", left, expression(p, 80), p)
  of pxAmp: # 90
    result = newBinary("and", left, expression(p, 90), p)
  of pxEquals: # 100
    result = newBinary("==", left, expression(p, 100), p)
  of pxNeq: # 100
    result = newBinary("!=", left, expression(p, 100), p)
  of pxLt: # 110
    result = newBinary("<", left, expression(p, 110), p)
  of pxLe: # 110
    result = newBinary("<=", left, expression(p, 110), p)
  of pxGt: # 110
    result = newBinary(">", left, expression(p, 110), p)
  of pxGe: # 110
    result = newBinary(">=", left, expression(p, 110), p)
  of pxShl: # 120
    result = newBinary("shl", left, expression(p, 120), p)
  of pxShr: # 120
    result = newBinary("shr", left, expression(p, 120), p)
  of pxPlus: # 130
    result = newNodeP(nkInfix, p)
    addSon(result, newIdentNodeP("+", p), left)
    addSon(result, expression(p, 130))
  of pxMinus: # 130
    result = newNodeP(nkInfix, p)
    addSon(result, newIdentNodeP("-", p), left)
    addSon(result, expression(p, 130))
  of pxStar: # 140
    if p.tok.xkind in {pxAngleRi, pxComma} and pfCpp in p.options.flags:
      result = newPointerTy(p, left)
    else:
      result = newNodeP(nkInfix, p)
      addSon(result, newIdentNodeP("*", p), left)
      addSon(result, expression(p, 140))
  of pxSlash: # 140
    result = newNodeP(nkInfix, p)
    addSon(result, newIdentNodeP("div", p), left)
    addSon(result, expression(p, 140))
  of pxMod: # 140
    result = newNodeP(nkInfix, p)
    addSon(result, newIdentNodeP("mod", p), left)
    addSon(result, expression(p, 140))
    # .* ->* == 150
  of pxPlusPlus: # 160
    result = newNodeP(nkCall, p)
    addSon(result, newIdentNodeP("inc", p), left)
  of pxMinusMinus: # 160
    result = newNodeP(nkCall, p)
    addSon(result, newIdentNodeP("dec", p), left)
  of pxParLe: # 160
    result = newNodeP(nkCall, p)
    addSon(result, left)
    while p.tok.xkind != pxParRi:
      var a = expression(p, 29)
      addSon(result, a)
      while p.tok.xkind == pxComma:
        getTok(p, a)
        a = expression(p, 29)
        addSon(result, a)
    eat(p, pxParRi, result)
  of pxDot: # 160
    result = newNodeP(nkDotExpr, p)
    addSon(result, left)
    addSon(result, skipIdent(p, skField))
  of pxArrow, pxArrowStar: # 160
    result = newNodeP(nkDotExpr, p)
    addSon(result, left)
    addSon(result, skipIdent(p, skField))
  of pxBracketLe: # 160
    result = newNodeP(nkBracketExpr, p)
    addSon(result, left, expression(p))
    eat(p, pxBracketRi, result)
    # :: == 170
  else:
    result = left

proc expression(p: var Parser, rbp: int = 0): PNode =
  var tok = p.tok[]
  getTok(p, result)

  result = startExpression(p, tok)
  while rbp < leftBindingPower(p, p.tok):
    tok = p.tok[]
    getTok(p, result)
    result = leftExpression(p, tok, result)

# Statements

proc buildStmtList(a: PNode): PNode =
  if a.kind == nkStmtList: result = a
  else:
    result = newNodeI(nkStmtList, a.info)
    addSon(result, a)

proc nestedStatement(p: var Parser): PNode =
  # careful: We need to translate:
  # if (x) if (y) stmt;
  # into:
  # if x:
  #   if x:
  #     stmt
  #
  # Nim requires complex statements to be nested in whitespace!
  const
    complexStmt = {nkProcDef, nkMethodDef, nkConverterDef, nkMacroDef,
      nkTemplateDef, nkIteratorDef, nkIfStmt,
      nkWhenStmt, nkForStmt, nkWhileStmt, nkCaseStmt, nkVarSection,
      nkConstSection, nkTypeSection, nkTryStmt, nkBlockStmt, nkStmtList,
      nkCommentStmt, nkStmtListExpr, nkBlockExpr, nkStmtListType, nkBlockType}
  result = statement(p)
  if result.kind in complexStmt:
    result = buildStmtList(result)

proc expressionStatement(p: var Parser): PNode =
  # do not skip the comment after a semicolon to make a new nkCommentStmt
  if p.tok.xkind == pxSemicolon:
    getTok(p)
    result = emptyNode
  else:
    let semicolonRequired = p.tok.xkind != pxVerbatim
    result = expression(p)
    if p.tok.xkind == pxSemicolon: getTok(p)
    elif semicolonRequired: parMessage(p, errGenerated, "expected ';'")
  assert result != nil

proc parseIf(p: var Parser): PNode =
  # we parse additional "else if"s too here for better Nimrod code
  result = newNodeP(nkIfStmt, p)
  while true:
    getTok(p) # skip ``if``
    var branch = newNodeP(nkElifBranch, p)
    eat(p, pxParLe, branch)
    addSon(branch, expression(p))
    eat(p, pxParRi, branch)
    addSon(branch, nestedStatement(p))
    addSon(result, branch)
    skipCom(p, branch)
    if p.tok.s == "else":
      getTok(p, result)
      if p.tok.s != "if":
        # ordinary else part:
        branch = newNodeP(nkElse, p)
        addSon(branch, nestedStatement(p))
        addSon(result, branch)
        break
    else:
      break

proc parseWhile(p: var Parser): PNode =
  result = newNodeP(nkWhileStmt, p)
  getTok(p, result)
  eat(p, pxParLe, result)
  addSon(result, expression(p))
  eat(p, pxParRi, result)
  addSon(result, nestedStatement(p))

proc embedStmts(sl, a: PNode)

proc parseDoWhile(p: var Parser): PNode =
  # parsing
  result = newNodeP(nkWhileStmt, p)
  getTok(p, result)
  var stm = nestedStatement(p)
  eat(p, "while", result)
  eat(p, pxParLe, result)
  var exp = expression(p)
  eat(p, pxParRi, result)
  if p.tok.xkind == pxSemicolon: getTok(p)

  # while true:
  #   stmt
  #   if not expr:
  #     break
  addSon(result, newIdentNodeP("true", p))

  stm = buildStmtList(stm)

  # get the last exp if it is a stmtlist
  var cleanedExp = exp
  if exp.kind == nkStmtList:
    cleanedExp = exp.sons[exp.len-1]
    exp.sons = exp.sons[0..exp.len-2]
    embedStmts(stm, exp)

  var notExp = newNodeP(nkPrefix, p)
  addSon(notExp, newIdentNodeP("not", p))
  addSon(notExp, cleanedExp)

  var brkStm = newNodeP(nkBreakStmt, p)
  addSon(brkStm, emptyNode)

  var ifStm = newNodeP(nkIfStmt, p)
  var ifBranch = newNodeP(nkElifBranch, p)
  addSon(ifBranch, notExp)
  addSon(ifBranch, brkStm)
  addSon(ifStm, ifBranch)

  embedStmts(stm, ifStm)

  addSon(result, stm)

proc declarationOrStatement(p: var Parser): PNode =
  if p.tok.xkind != pxSymbol:
    result = expressionStatement(p)
  elif declKeyword(p, p.tok.s):
    result = declaration(p)
  else:
    # ordinary identifier:
    saveContext(p)
    getTok(p) # skip identifier to look ahead

    if pfCpp in p.options.flags and p.tok.xkind == pxScope:
      # match qualified identifier eg. `std::ostream`
      backtrackContext(p)
      saveContext(p)
      let retType = typeAtom(p)
      discard pointer(p, retType)
      if p.tok.s == "operator":
        backtrackContext(p)
        return declaration(p)
      backtrackContext(p)

    case p.tok.xkind
    of pxSymbol, pxStar, pxLt, pxAmp, pxAmpAmp:
      # we parse
      # a b
      # a * b
      # always as declarations! This is of course not correct, but good
      # enough for most real world C code out there.
      backtrackContext(p)
      result = declaration(p)
    of pxColon:
      # it is only a label:
      closeContext(p)
      getTok(p)
      result = statement(p)
    else:
      backtrackContext(p)
      result = expressionStatement(p)
  assert result != nil

proc parseTuple(p: var Parser, statements: PNode, isUnion: bool): PNode =
  parseStructBody(p, statements, isUnion, nkTupleTy)

proc parseTrailingDefinedIdents(p: var Parser, result, baseTyp: PNode) =
  var varSection = newNodeP(nkVarSection, p)
  while p.tok.xkind notin {pxEof, pxSemicolon}:
    var t = pointer(p, baseTyp)
    expectIdent(p)
    var def = newNodeP(nkIdentDefs, p)
    addSon(def, varIdent(p.tok.s, p))
    getTok(p, def)
    addSon(def, parseTypeSuffix(p, t))
    addInitializer(p, def)
    addSon(varSection, def)
    if p.tok.xkind != pxComma: break
    getTok(p, def)
  eat(p, pxSemicolon)
  if sonsLen(varSection) > 0:
    addSon(result, varSection)

proc parseStandaloneStruct(p: var Parser, isUnion: bool;
                           genericParams: PNode): PNode =
  result = newNodeP(nkStmtList, p)
  saveContext(p)
  getTok(p, result) # skip "struct" or "union"
  var origName = ""
  if p.tok.xkind == pxSymbol:
    markTypeIdent(p, nil)
    origName = p.tok.s
    getTok(p, result)
  if p.tok.xkind in {pxCurlyLe, pxSemiColon, pxColon}:
    if origName.len > 0:
      var name = mangledIdent(origName, p, skType)
      var t = parseStruct(p, result, isUnion)
      var typeSection = newNodeP(nkTypeSection, p)
      addTypeDef(typeSection, structPragmas(p, name, origName), t, genericParams)
      addSon(result, typeSection)
      parseTrailingDefinedIdents(p, result, name)
    else:
      var t = parseTuple(p, result, isUnion)
      parseTrailingDefinedIdents(p, result, t)
  else:
    backtrackContext(p)
    result = declaration(p)

proc parseFor(p: var Parser, result: PNode) =
  # 'for' '(' expression_statement expression_statement expression? ')'
  #   statement
  getTok(p, result)
  eat(p, pxParLe, result)
  var initStmt = declarationOrStatement(p)
  if initStmt.kind != nkEmpty:
    embedStmts(result, initStmt)
  var w = newNodeP(nkWhileStmt, p)
  var condition = expressionStatement(p)
  if condition.kind == nkEmpty: condition = newIdentNodeP("true", p)
  addSon(w, condition)
  var step = if p.tok.xkind != pxParRi: expression(p) else: emptyNode
  eat(p, pxParRi, step)
  var loopBody = nestedStatement(p)
  if step.kind != nkEmpty:
    loopBody = buildStmtList(loopBody)
    embedStmts(loopBody, step)
  addSon(w, loopBody)
  addSon(result, w)

proc switchStatement(p: var Parser): PNode =
  result = newNodeP(nkStmtList, p)
  while true:
    if p.tok.xkind in {pxEof, pxCurlyRi}: break
    case p.tok.s
    of "break":
      getTok(p, result)
      eat(p, pxSemicolon, result)
      break
    of "return", "continue", "goto":
      addSon(result, statement(p))
      break
    of "case", "default":
      break
    else: discard
    addSon(result, statement(p))
  if sonsLen(result) == 0:
    # translate empty statement list to Nimrod's ``nil`` statement
    result = newNodeP(nkNilLit, p)

proc rangeExpression(p: var Parser): PNode =
  # We support GCC's extension: ``case expr...expr:``
  result = constantExpression(p)
  if p.tok.xkind == pxDotDotDot:
    getTok(p, result)
    var a = result
    var b = constantExpression(p)
    result = newNodeP(nkRange, p)
    addSon(result, a)
    addSon(result, b)

proc parseSwitch(p: var Parser): PNode =
  # We cannot support Duff's device or C's crazy switch syntax. We just support
  # sane usages of switch. ;-)
  result = newNodeP(nkCaseStmt, p)
  getTok(p, result)
  eat(p, pxParLe, result)
  addSon(result, expression(p))
  eat(p, pxParRi, result)
  eat(p, pxCurlyLe, result)
  var b: PNode
  while (p.tok.xkind != pxCurlyRi) and (p.tok.xkind != pxEof):
    case p.tok.s
    of "default":
      b = newNodeP(nkElse, p)
      getTok(p, b)
      eat(p, pxColon, b)
    of "case":
      b = newNodeP(nkOfBranch, p)
      while p.tok.xkind == pxSymbol and p.tok.s == "case":
        getTok(p, b)
        addSon(b, rangeExpression(p))
        eat(p, pxColon, b)
    else:
      parMessage(p, errXExpected, "case")
    addSon(b, switchStatement(p))
    addSon(result, b)
    if b.kind == nkElse: break
  eat(p, pxCurlyRi)

proc addStmt(sl, a: PNode) =
  # merge type sections if possible:
  if a.kind != nkTypeSection or sonsLen(sl) == 0 or
      lastSon(sl).kind != nkTypeSection:
    addSon(sl, a)
  else:
    var ts = lastSon(sl)
    for i in 0..sonsLen(a)-1: addSon(ts, a.sons[i])

proc embedStmts(sl, a: PNode) =
  if a.kind != nkStmtList:
    addStmt(sl, a)
  else:
    for i in 0..sonsLen(a)-1:
      if a[i].kind != nkEmpty: embedStmts(sl, a[i])

proc compoundStatement(p: var Parser; newScope=true): PNode =
  result = newNodeP(nkStmtList, p)
  eat(p, pxCurlyLe)
  if newScope: inc(p.scopeCounter)
  while p.tok.xkind notin {pxEof, pxCurlyRi}:
    var a = statement(p)
    if a.kind == nkEmpty: break
    embedStmts(result, a)
  if sonsLen(result) == 0:
    # translate ``{}`` to Nim's ``discard`` statement
    result = newNodeP(nkDiscardStmt, p)
    result.add(emptyNode)
  if newScope: dec(p.scopeCounter)
  eat(p, pxCurlyRi)

proc applyGenericParams(t, gp: PNode): PNode =
  if gp.kind == nkEmpty:
    result = t
  else:
    result = newNodeI(nkBracketExpr, t.info)
    result.add t
    for x in gp:
      if x.len > 1 and x[1].kind == nkStaticTy:
        result.add x[0]
      else:
        result.add x

proc createThis(p: var Parser; genericParams: PNode): PNode =
  result = newNodeP(nkIdentDefs, p)
  var t = newNodeP(nkVarTy, p)
  t.add(p.currentClass.applyGenericParams(genericParams))
  addSon(result, newIdentNodeP("this", p), t, emptyNode)

proc parseConstructor(p: var Parser, pragmas: PNode, isDestructor: bool;
                      genericParams, genericParamsThis: PNode): PNode =
  var origName = p.tok.s
  getTok(p)

  result = newNodeP(nkProcDef, p)
  var rettyp = if isDestructor: newNodeP(nkNilLit, p)
               else: mangledIdent(origName, p, skType).applyGenericParams(
                  genericParamsThis)

  let oname = if isDestructor: p.options.destructor & origName
              else: p.options.constructor & origName
  var name = mangledIdent(oname, p, skProc)
  var params = newNodeP(nkFormalParams, p)
  discard addReturnType(params, rettyp)
  if isDestructor: params.add(createThis(p, genericParamsThis))

  if p.tok.xkind == pxParLe:
    parseFormalParams(p, params, pragmas)
  if p.tok.xkind == pxSymbol and p.tok.s == "const":
    addSon(pragmas, newIdentNodeP("noSideEffect", p))
  if pfCDecl in p.options.flags:
    addSon(pragmas, newIdentNodeP("cdecl", p))
  elif pfStdcall in p.options.flags:
    addSon(pragmas, newIdentNodeP("stdcall", p))
  if not isDestructor: addSon(pragmas, newIdentNodeP("constructor", p))
  if p.tok.xkind == pxColon:
    # skip initializer list:
    while true:
      getTok(p)
      discard expression(p)
      if p.tok.xkind != pxComma: break
  # no pattern, no exceptions:
  addSon(result, exportSym(p, name, origName), emptyNode, genericParams)
  addSon(result, params, pragmas, emptyNode) # no exceptions
  addSon(result, emptyNode) # no body
  skipThrowSpecifier(p)
  case p.tok.xkind
  of pxSemicolon: getTok(p)
  of pxCurlyLe:
    let body = compoundStatement(p)
    if pfKeepBodies in p.options.flags:
      result.sons[bodyPos] = body
  of pxAsgn:
    # '= default;' C++11 defaulted constructor
    getTok(p)
    if p.tok.s == "default":
      eat(p, pxSymbol)
      eat(p, pxSemicolon)
    else:
      parMessage(p, errGenerated, "expected 'default'")
  else:
    parMessage(p, errGenerated, "expected ';'")
  if result.sons[bodyPos].kind == nkEmpty:
    if isDestructor:
      doImportCpp("#.~" & origName & "()", pragmas, p)
    else:
      doImportCpp(p.currentNamespace & origName & "(@)", pragmas, p)
  elif isDestructor:
    addSon(pragmas, newIdentNodeP("destructor", p))
  if sonsLen(result.sons[pragmasPos]) == 0:
    result.sons[pragmasPos] = emptyNode

proc parseMethod(p: var Parser, origName: string, rettyp, pragmas: PNode,
                 isStatic, isOperator, hasPointlessPar: bool;
                 genericParams, genericParamsThis: PNode): PNode =
  result = newNodeP(nkProcDef, p)
  var params = newNodeP(nkFormalParams, p)
  if addReturnType(params, rettyp):
    addDiscardable(origName, pragmas, p)

  var thisDef: PNode
  if not isStatic:
    # declare 'this':
    thisDef = createThis(p, genericParamsThis)
    params.add(thisDef)

  parseFormalParams(p, params, pragmas)
  if hasPointlessPar: eat(p, pxParRi)
  if p.tok.xkind == pxSymbol and p.tok.s == "const":
    addSon(pragmas, newIdentNodeP("noSideEffect", p))
    getTok(p, result)
    if not thisDef.isNil:
      # fix the type of the 'this' parameter:
      thisDef.sons[1] = thisDef.sons[1].sons[0]
  if pfCDecl in p.options.flags:
    addSon(pragmas, newIdentNodeP("cdecl", p))
  elif pfStdcall in p.options.flags:
    addSon(pragmas, newIdentNodeP("stdcall", p))
  # no pattern, no exceptions:
  var methodName = mangledIdent(origName, p, skProc)
  if isOperator:
    let x = methodName
    methodName = newNodeP(nkAccQuoted, p)
    methodName.add x
  addSon(result, exportSym(p, methodName, origName),
         emptyNode, genericParams)
  addSon(result, params, pragmas, emptyNode) # no exceptions
  addSon(result, emptyNode) # no body
  skipThrowSpecifier(p)
  case p.tok.xkind
  of pxSemicolon: getTok(p)
  of pxCurlyLe:
    let body = compoundStatement(p)
    if pfKeepBodies in p.options.flags:
      result.sons[bodyPos] = body
  of pxAsgn:
    # '= 0' aka abstract method:
    getTok(p)
    eat(p, pxIntLit)
    eat(p, pxSemicolon)
  else:
    parMessage(p, errGenerated, "expected ';'")
  if result.sons[bodyPos].kind == nkEmpty:
    if isOperator:
      case origName
      of "+=", "-=", "*=", "/=", "<<=", ">>=", "|=", "&=",
          "||=", "~=", "%=", "^=":
        # we remove the pointless return type used for chaining:
        params.sons[0] = emptyNode
        doImportCpp("(# " & origName & " #)", pragmas, p)
      of "==", "<=", "<", ">=", ">", "&", "&&", "|", "||", "%", "/", "^",
         "!=", "<<", ">>", "->", "->*":
        doImportCpp("(# " & origName & " #)", pragmas, p)
      of "+", "-", "*":
        # binary operator? check against 3 because return type always has a slot
        if params.len >= 3:
          doImportCpp("(# " & origName & " #)", pragmas, p)
        else:
          doImportCpp("(" & origName & " #)", pragmas, p)
      of "++", "--", "!", "~":
        doImportCpp("(" & origName & " #)", pragmas, p)
      of "()": doImportCpp("#(@)", pragmas, p)
      of "[]": doImportCpp("#[@]", pragmas, p)
      of ",": doImportCpp("#,@", pragmas, p)
      else:
        # XXX the above list is exhaustive really
        doImportCpp(p.currentClassOrig & "::operator " & origName, pragmas, p)
    elif isStatic:
      doImportCpp(p.currentNamespace & p.currentClassOrig & "::" &
                  origName & "(@)", pragmas, p)
    else:
      doImportCpp(origName, pragmas, p)
  if sonsLen(result.sons[pragmasPos]) == 0:
    result.sons[pragmasPos] = emptyNode


proc parseStandaloneClass(p: var Parser, isStruct: bool;
                          genericParams: PNode): PNode

proc followedByParLe(p: var Parser): bool =
  saveContext(p)
  getTok(p) # skip Identifier
  result = p.tok.xkind == pxParLe
  backtrackContext(p)

proc parseTemplate(p: var Parser): PNode =
  result = emptyNode
  if p.tok.xkind == pxSymbol and p.tok.s == "template":
    getTok(p)
    if p.tok.xkind == pxLt and isTemplateAngleBracket(p):
      result = newNodeP(nkGenericParams, p)
      getTok(p)
      if p.tok.xkind != pxAngleRi:
        while true:
          if p.tok.xkind == pxSymbol and
              (p.tok.s == "class" or p.tok.s == "typename"):
                getTok(p)
                var identDefs = newNodeP(nkIdentDefs, p)
                identDefs.addSon(skipIdent(p, skType), emptyNode, emptyNode)
                result.add identDefs
          if p.tok.xkind == pxSymbol and (isIntType(p.tok.s) or
              p.tok.s == "bool") and p.tok.s != "double" and
              p.tok.s != "float":
                var staticTy = newNodeP(nkStaticTy, p)
                staticTy.add(typeDesc(p))
                var identDefs = newNodeP(nkIdentDefs, p)
                identDefs.addSon(skipIdent(p, skType), staticTy, emptyNode)
                result.add identDefs
          if p.tok.xkind != pxComma: break
          getTok(p)
      eat(p, pxAngleRi)

proc getConverterCppType(p: var Parser): string =
  getTok(p) # skip "operator"
  saveContext(p)
  result = ""
  while true:
    case p.tok.xkind
    of pxStar, pxAmp, pxAmpAmp:
      result &= tokKindToStr(p.tok.xkind)
    of pxSymbol:
      result &= p.tok.s
    else: break
    getTok(p)
  backtrackContext(p)

proc parseClass(p: var Parser; isStruct: bool;
                stmtList, genericParams: PNode): PNode =
  result = newNodeP(nkObjectTy, p)
  addSon(result, emptyNode, emptyNode) # no pragmas, no inheritance

  var recList = newNodeP(nkRecList, p)
  addSon(result, recList)
  parseInheritance(p, result)
  # 'class foo;' <- forward declaration; in order to avoid multiple definitions,
  # we ignore those completely:
  if p.tok.xkind == pxSemicolon:
    eat(p, pxSemicolon, result)
    return nil
  eat(p, pxCurlyLe, result)
  var private = not isStruct
  var pragmas = newNodeP(nkPragma, p)
  while p.tok.xkind notin {pxEof, pxCurlyRi}:
    skipCom(p, stmtList)
    # empty visibility sections are allowed and used extensively for wxWidgets:
    while true:
      if p.tok.xkind == pxSymbol and (p.tok.s == "private" or
                                      p.tok.s == "protected"):
        getTok(p, result)
        eat(p, pxColon, result)
        private = true
      elif p.tok.xkind == pxSymbol and p.tok.s == "public":
        getTok(p, result)
        eat(p, pxColon, result)
        private = false
      else:
        break
    let tmpl = parseTemplate(p)
    var gp: PNode
    if tmpl.kind != nkEmpty:
      if genericParams.kind != nkEmpty:
        gp = genericParams.copyTree
        for x in tmpl: gp.add x
      else:
        gp = tmpl
    else:
      gp = genericParams
    if p.tok.xkind == pxSymbol and (p.tok.s == "friend" or p.tok.s == "using"):
      # we skip friend declarations:
      while p.tok.xkind notin {pxEof, pxSemicolon}: getTok(p)
      eat(p, pxSemicolon)
    elif p.tok.xkind == pxSymbol and p.tok.s == "enum":
      let x = enumSpecifier(p)
      if not private or pfKeepBodies in p.options.flags: stmtList.add(x)
    elif p.tok.xkind == pxSymbol and p.tok.s == "typedef":
      let x = parseTypeDef(p)
      if not private or pfKeepBodies in p.options.flags: stmtList.add(x)
    elif p.tok.xkind == pxSymbol and(p.tok.s == "struct" or p.tok.s == "class"):
      let x = parseStandaloneClass(p, isStruct=p.tok.s == "struct", gp)
      if not private or pfKeepBodies in p.options.flags: stmtList.add(x)
    elif p.tok.xkind == pxSymbol and p.tok.s == "union":
      let x = parseStandaloneStruct(p, isUnion=true, gp)
      if not private or pfKeepBodies in p.options.flags: stmtList.add(x)
    elif p.tok.xkind == pxCurlyRi: discard
    else:
      if pragmas.len != 0: pragmas = newNodeP(nkPragma, p)
      parseCallConv(p, pragmas)
      var isStatic = false
      if p.tok.xkind == pxSymbol and p.tok.s == "virtual":
        getTok(p, stmtList)
      if p.tok.xkind == pxSymbol and p.tok.s == "explicit":
        getTok(p, stmtList)
      if p.tok.xkind == pxSymbol and p.tok.s == "static":
        getTok(p, stmtList)
        isStatic = true
      # skip constexpr for now
      if p.tok.xkind == pxSymbol and p.tok.s == "constexpr":
        getTok(p, stmtList)

      parseCallConv(p, pragmas)
      if p.tok.xkind == pxSymbol and p.tok.s == p.currentClassOrig and
          followedByParLe(p):
        # constructor
        let cons = parseConstructor(p, pragmas, isDestructor=false,
                                    gp, genericParams)
        if not private or pfKeepBodies in p.options.flags: stmtList.add(cons)
      elif p.tok.xkind == pxTilde:
        # destructor
        getTok(p, stmtList)
        if p.tok.xkind == pxSymbol and p.tok.s == p.currentClassOrig:
          let des = parseConstructor(p, pragmas, isDestructor=true,
                                     gp, genericParams)
          if not private or pfKeepBodies in p.options.flags: stmtList.add(des)
        else:
          parMessage(p, errGenerated, "invalid destructor")
      elif p.tok.xkind == pxSymbol and p.tok.s == "operator":
        let origName = getConverterCppType(p)
        var baseTyp = typeAtom(p)
        var t = pointer(p, baseTyp)
        let meth = parseMethod(p, origName, t, pragmas, isStatic, true,
                                false, gp, genericParams)
        if not private or pfKeepBodies in p.options.flags:
          meth.kind = nkConverterDef
          # don't add trivial operators that Nim ends up using anyway:
          if origName notin ["=", "!=", ">", ">="]:
            stmtList.add(meth)
      elif p.tok.xkind == pxBracketLe and pfCpp in p.options.flags:
        # c++11 attribute
        eat(p, pxBracketLe)
        eat(p, pxBracketLe)
        # just ignore for now, could convert into pragma eg. deprecated
        while p.tok.xkind != pxBracketRi:
          getTok(p)
        eat(p, pxBracketRi)
        eat(p, pxBracketRi)
      else:
        # field declaration or method:
        if p.tok.xkind == pxSemicolon:
          getTok(p)
          skipCom(p, stmtList)
        var baseTyp = typeAtom(p)
        while true:
          var def = newNodeP(nkIdentDefs, p)
          var t = pointer(p, baseTyp)
          var hasPointlessPar = p.tok.xkind == pxParLe
          if hasPointlessPar: getTok(p)
          var origName: string
          if p.tok.xkind == pxSymbol:
            if p.tok.s == "operator":
              origName = ""
              var isConverter = parseOperator(p, origName)
              let meth = parseMethod(p, origName, t, pragmas, isStatic, true,
                                     false, gp, genericParams)
              if not private or pfKeepBodies in p.options.flags:
                if isConverter: meth.kind = nkConverterDef
                # don't add trivial operators that Nim ends up using anyway:
                if origName notin ["=", "!=", ">", ">="]:
                  stmtList.add(meth)
              break
            origName = p.tok.s

          var i = parseField(p, nkRecList)
          if origName.len > 0 and p.tok.xkind == pxParLe:
            let meth = parseMethod(p, origName, t, pragmas, isStatic, false,
                                   hasPointlessPar, gp, genericParams)
            if not private or pfKeepBodies in p.options.flags:
              stmtList.add(meth)
          else:
            if hasPointlessPar: eat(p, pxParRi)
            t = parseTypeSuffix(p, t)
            var value = emptyNode
            if p.tok.xkind == pxAsgn:
              getTok(p, def)
              value = assignmentExpression(p)
            if not private or pfKeepBodies in p.options.flags:
              addSon(def, i, t, value)
            if not isStatic: addSon(recList, def)
          if p.tok.xkind != pxComma: break
          getTok(p, def)
        if p.tok.xkind == pxSemicolon:
          if recList.len > 0:
            getTok(p, lastSon(recList))
          else:
            getTok(p, recList)
    opt(p, pxSemicolon, nil)
  eat(p, pxCurlyRi, result)

proc parseStandaloneClass(p: var Parser, isStruct: bool;
                          genericParams: PNode): PNode =
  result = newNodeP(nkStmtList, p)
  saveContext(p)
  getTok(p, result) # skip "class" or "struct"
  let oldClass = p.currentClass
  var oldClassOrig = p.currentClassOrig
  p.currentClassOrig = ""
  if p.tok.xkind == pxSymbol:
    markTypeIdent(p, nil)
    p.currentClassOrig = p.tok.s
    getTok(p, result)
    p.currentClass = mangledIdent(p.currentClassOrig, p, skType)
  else:
    p.currentClass = nil
  if p.tok.xkind in {pxCurlyLe, pxSemiColon, pxColon}:
    if p.currentClass != nil:
      p.options.classes[p.currentClassOrig] = "true"

      var typeSection = newNodeP(nkTypeSection, p)
      addSon(result, typeSection)

      var name = p.currentClass #mangledIdent(p.currentClassOrig, p, skType)
      var t = parseClass(p, isStruct, result, genericParams)
      if t.isNil:
        result = newNodeP(nkDiscardStmt, p)
        result.add(newStrNodeP(nkStrLit, "forward decl of " & p.currentClassOrig, p))
        p.currentClass = oldClass
        p.currentClassOrig = oldClassOrig
        p.options.classes[p.currentClassOrig] = "true"
        return result
      addTypeDef(typeSection, structPragmas(p, name, p.currentClassOrig), t,
                 genericParams)
      parseTrailingDefinedIdents(p, result, name)
    else:
      var t = parseTuple(p, result, isUnion=false)
      parseTrailingDefinedIdents(p, result, t)
  else:
    backtrackContext(p)
    result = declaration(p)
  p.currentClass = oldClass
  p.currentClassOrig = oldClassOrig

proc unwrap(a: PNode): PNode =
  if a.kind == nkPar:
    return a.sons[0]
  return a

include cpp

proc fullTemplate(p: var Parser): PNode =
  let tmpl = parseTemplate(p)
  expectIdent(p)
  case p.tok.s
  of "union": result = parseStandaloneStruct(p, isUnion=true, tmpl)
  of "struct": result = parseStandaloneClass(p, isStruct=true, tmpl)
  of "class": result = parseStandaloneClass(p, isStruct=false, tmpl)
  else: result = declaration(p, tmpl)

proc statement(p: var Parser): PNode =
  case p.tok.xkind
  of pxSymbol:
    case p.tok.s
    of "if": result = parseIf(p)
    of "switch": result = parseSwitch(p)
    of "while": result = parseWhile(p)
    of "do": result = parseDoWhile(p)
    of "for":
      result = newNodeP(nkStmtList, p)
      parseFor(p, result)
    of "goto":
      # we cannot support "goto"; in hand-written C, "goto" is most often used
      # to break a block, so we convert it to a break statement with label.
      result = newNodeP(nkBreakStmt, p)
      getTok(p)
      addSon(result, skipIdent(p, skLabel))
      eat(p, pxSemicolon)
    of "continue":
      result = newNodeP(nkContinueStmt, p)
      getTok(p)
      eat(p, pxSemicolon)
      addSon(result, emptyNode)
    of "break":
      result = newNodeP(nkBreakStmt, p)
      getTok(p)
      eat(p, pxSemicolon)
      addSon(result, emptyNode)
    of "return":
      result = newNodeP(nkReturnStmt, p)
      getTok(p)
      if p.tok.xkind == pxSemicolon:
        addSon(result, emptyNode)
      else:
        addSon(result, unwrap(expression(p)))
      eat(p, pxSemicolon)
    of "enum": result = enumSpecifier(p)
    of "typedef": result = parseTypeDef(p)
    of "union": result = parseStandaloneStruct(p, isUnion=true, emptyNode)
    of "struct":
      if pfCpp in p.options.flags:
        result = parseStandaloneClass(p, isStruct=true, emptyNode)
      else:
        result = parseStandaloneStruct(p, isUnion=false, emptyNode)
    of "class":
      if pfCpp in p.options.flags:
        result = parseStandaloneClass(p, isStruct=false, emptyNode)
      else:
        result = declarationOrStatement(p)
    of "namespace":
      if pfCpp in p.options.flags:
        getTok(p)
        expectIdent(p)
        var oldNamespace = p.currentNamespace
        p.currentNamespace &= p.tok.s & "::"
        getTok(p)
        if p.tok.xkind != pxCurlyLe:
          parMessage(p, errGenerated, "expected " & tokKindToStr(pxCurlyLe))
        result = compoundStatement(p, newScope=false)
        p.currentNamespace = oldNamespace
      else:
        result = declarationOrStatement(p)
    of "template":
      if pfCpp in p.options.flags:
        result = fullTemplate(p)
      else:
        result = declarationOrStatement(p)
    of "using":
      if pfCpp in p.options.flags:
        while p.tok.xkind notin {pxEof, pxSemicolon}: getTok(p)
        eat(p, pxSemicolon)
        result = newNodeP(nkNilLit, p)
      else:
        result = declarationOrStatement(p)
    else: result = declarationOrStatement(p)
  of pxCurlyLe:
    result = compoundStatement(p)
  of pxDirective, pxDirectiveParLe:
    result = parseDir(p, statement)
  of pxLineComment, pxStarComment:
    result = newNodeP(nkCommentStmt, p)
    skipCom(p, result)
  of pxSemicolon:
    # empty statement:
    getTok(p)
    if p.tok.xkind in {pxLineComment, pxStarComment}:
      result = newNodeP(nkCommentStmt, p)
      skipCom(p, result)
    else:
      result = newNodeP(nkNilLit, p)
  else:
    result = expressionStatement(p)
  assert result != nil

proc parseUnit(p: var Parser): PNode =
  try:
    result = newNodeP(nkStmtList, p)
    getTok(p) # read first token
    while p.tok.xkind != pxEof:
      var s = statement(p)
      if s.kind != nkEmpty: embedStmts(result, s)
  except ERetryParsing:
    parMessage(p, errGenerated, getCurrentExceptionMsg())
    #"Uncaught parsing exception raised")
