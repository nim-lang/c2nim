#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements an ANSI C / C++ parser.
## It translates a C source file into a Nim AST. Then the renderer can be
## used to convert the AST to its text representation.
##
## The parser is a hand-written LL(infinity) parser. We accomplish this
## by using exceptions to bail out of failed parsing attemps and via
## backtracking. The tokens are stored in a singly linked list so we can
## easily go back. The token list is patched so that `>>` is converted to
## `> >` for C++ template support.

import
  os, compiler/llstream, compiler/renderer, clexer, compiler/idents, strutils,
  pegs, compiler/ast, compiler/msgs,
  strtabs, hashes, algorithm, compiler/nversion

when declared(NimCompilerApiVersion):
  import compiler / lineinfos

  proc getIdent(s: string): PIdent = getIdent(identCache, s)
  template emptyNode: untyped = newNode(nkEmpty)

import pegs except Token, Tokkind

type
  ParserFlag* = enum
    pfStrict,         ## do not use the "best effort" parsing approach
                        ## with sync points.
    pfRefs,             ## use "ref" instead of "ptr" for C's typ*
    pfCDecl,            ## annotate procs with cdecl
    pfStdCall,          ## annotate procs with stdcall
    pfImportc,          ## annotate procs with importc
    pfNoConv,           ## annotate procs with noconv
    pfSkipInclude,      ## skip all ``#include``
    pfTypePrefixes,     ## all generated types start with 'T' or 'P'
    pfSkipComments,     ## do not generate comments
    pfCpp,              ## process C++
    pfIgnoreRValueRefs, ## transform C++'s 'T&&' to 'T'
    pfKeepBodies,       ## do not skip C++ method bodies
    pfAssumeIfIsTrue,   ## assume #if is true
    pfStructStruct,     ## do not treat struct Foo Foo as a forward decl
    pfReorderComments   ## do not treat struct Foo Foo as a forward decl

  Macro* = object
    name*: string
    params*: int # number of parameters; 0 for empty (); -1 for no () at all
    body*: seq[ref Token] # can contain pxMacroParam tokens

  ParserOptions = object ## shared parser state!
    flags*: set[ParserFlag]
    renderFlags*: TRenderFlags
    prefixes, suffixes: seq[string]
    assumeDef, assumenDef: seq[string]
    mangleRules: seq[tuple[pattern: Peg, frmt: string]]
    privateRules: seq[Peg]
    dynlibSym, headerOverride: string
    macros*: seq[Macro]
    toMangle: StringTableRef
    classes: StringTableRef
    toPreprocess: StringTableRef
    inheritable: StringTableRef
    debugMode, followNep1: bool
    useHeader, importdefines, importfuncdefines: bool
    discardablePrefixes: seq[string]
    constructor, destructor, importcLit: string
    exportPrefix*: string
    paramPrefix*: string
    isArray: StringTableRef

  PParserOptions* = ref ParserOptions

  Section* = ref object # used for "parseClassSnippet"
    genericParams: PNode
    pragmas: PNode
    private: bool

  Parser* = object
    lex: Lexer
    tok: ref Token       # current token
    header: string
    options: PParserOptions
    backtrack: seq[ref Token]
    backtrackB: seq[(ref Token, bool)] # like backtrack, but with the possibility to ignore errors
    inTypeDef: int
    scopeCounter: int
    currentClass: PNode   # type that needs to be added as 'this' parameter
    currentClassOrig: string # original class name
    classHierarchy: seq[string] # used for nested types
    classHierarchyGP: seq[PNode]
    currentNamespace: string
    inAngleBracket, inPreprocessorExpr: int
    lastConstType: PNode # another hack to be able to translate 'const Foo& foo'
                         # to 'foo: Foo' and not 'foo: var Foo'.
    continueActions: seq[PNode]
    currentSection: Section # can be nil
    anoTypeCount: int

  ReplaceTuple* = array[0..1, string]

  ERetryParsing = object of ValueError

  SectionParser = proc(p: var Parser): PNode {.nimcall.}

proc parseDir(p: var Parser; sectionParser: SectionParser): PNode
proc addTypeDef(section, name, t, genericParams: PNode)
proc parseStruct(p: var Parser, stmtList: PNode): PNode
proc parseStructBody(p: var Parser, stmtList: PNode,
                     kind: TNodeKind = nkRecList): PNode
proc parseClass(p: var Parser; isStruct: bool;
                stmtList, genericParams: PNode): PNode
proc inheritedGenericParams(p: Parser) : PNode

proc newParserOptions*(): PParserOptions =
  PParserOptions(
    prefixes: @[],
    suffixes: @[],
    assumeDef: @[],
    assumenDef: @["__cplusplus"],
    macros: @[],
    mangleRules: @[],
    privateRules: @[],
    discardablePrefixes: @[],
    flags: {},
    renderFlags: {},
    dynlibSym: "",
    headerOverride: "",
    toMangle: newStringTable(modeCaseSensitive),
    classes: newStringTable(modeCaseSensitive),
    toPreprocess: newStringTable(modeCaseSensitive),
    inheritable: newStringTable(modeCaseSensitive),
    constructor: "construct",
    destructor: "destroy",
    importcLit: "importc",
    exportPrefix: "",
    paramPrefix: "a",
    isArray: newStringTable(modeCaseSensitive))

proc setOption*(parserOptions: PParserOptions, key: string, val=""): bool =
  result = true
  case key.normalize
  of "strict": incl(parserOptions.flags, pfStrict)
  of "ref": incl(parserOptions.flags, pfRefs)
  of "dynlib": parserOptions.dynlibSym = val
  of "header":
    parserOptions.useHeader = true
    if val.len > 0: parserOptions.headerOverride = val
  of "importfuncdefines":
    parserOptions.importfuncdefines = true
  of "importdefines":
    parserOptions.importdefines = true
  of "cdecl": incl(parserOptions.flags, pfCdecl)
  of "stdcall": incl(parserOptions.flags, pfStdCall)
  of "importc": incl(parserOptions.flags, pfImportc)
  of "noconv": incl(parserOptions.flags, pfNoConv)
  of "prefix": parserOptions.prefixes.add(val)
  of "suffix": parserOptions.suffixes.add(val)
  of "paramprefix":
    if val.len > 0: parserOptions.paramPrefix = val
  of "assumedef": parserOptions.assumeDef.add(val)
  of "assumendef": parserOptions.assumenDef.add(val)
  of "mangle":
    let vals = val.split("=")
    parserOptions.mangleRules.add((parsePeg(vals[0]), vals[1]))
  of "stdints":
    let vals = (r"{u?}int{\d+}_t", r"$1int$2")
    parserOptions.mangleRules.add((parsePeg(vals[0]), vals[1]))
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
  of "reordercomments": incl(parserOptions.flags, pfReorderComments)
  of "isarray": parserOptions.isArray[val] = "true"
  else: result = false

proc openParser*(p: var Parser, filename: string,
                inputStream: PLLStream, options: PParserOptions) =
  openLexer(p.lex, filename, inputStream)
  p.options = options
  p.header = filename.extractFilename
  p.lex.debugMode = options.debugMode
  p.backtrack = @[]
  p.currentNamespace = ""
  p.currentClassOrig = ""
  p.classHierarchy = @[]
  p.classHierarchyGP = @[]
  new(p.tok)

proc parMessage(p: Parser, msg: TMsgKind, arg = "") =
  lexMessage(p.lex, msg, arg)

proc parError(p: Parser, arg = "") =
  # raise newException(Exception, arg)
  if p.backtrackB.len == 0:
    lexMessage(p.lex, errGenerated, arg)
  else:
    if p.backtrackB[^1][1]:
      lexMessage(p.lex, warnSyntaxError, arg)
    raise newException(ERetryParsing, arg)

proc closeParser*(p: var Parser) = closeLexer(p.lex)

proc saveContext(p: var Parser) = p.backtrack.add(p.tok)
# EITHER call 'closeContext' or 'backtrackContext':
proc closeContext(p: var Parser) = discard p.backtrack.pop()
proc backtrackContext(p: var Parser) = p.tok = p.backtrack.pop()

proc saveContextB(p: var Parser; produceWarnings=false) = p.backtrackB.add((p.tok, produceWarnings))
proc closeContextB(p: var Parser) = discard p.backtrackB.pop()
proc backtrackContextB(p: var Parser) = p.tok = p.backtrackB.pop()[0]

proc rawGetTok(p: var Parser) =
  if p.tok.next != nil:
    p.tok = p.tok.next
  elif p.backtrack.len == 0 and p.backtrackB.len == 0:
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
  else:
    parError(p, "token expected: " & tokKindToStr(xkind))

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
      kind = correspondingOpenPar(kind)
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
        parError(p, "wrong number of arguments")
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
        for t in items(arguments[tok.position]):
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
        for t in items(arguments[tok.position]):
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
    if idx >= 0 and p.inPreprocessorExpr == 0:
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
      n.info.line = p.tok.lineNumber.uint16
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
    # raise newException(Exception, "error")
    parError(p, "identifier expected, but got: " & debugTok(p.lex, p.tok[]))

proc eat(p: var Parser, xkind: Tokkind, n: PNode) =
  if p.tok.xkind == xkind: getTok(p, n)
  else: parError(p, "token expected: " & tokKindToStr(xkind) & " but got: " & tokKindToStr(p.tok.xkind))

proc eat(p: var Parser, xkind: Tokkind) =
  if p.tok.xkind == xkind: getTok(p)
  else: parError(p, "token expected: " & tokKindToStr(xkind) & " but got: " & tokKindToStr(p.tok.xkind))

proc eat(p: var Parser, tok: string, n: PNode) =
  if p.tok.s == tok: getTok(p, n)
  else: parError(p, "token expected: " & tok & " but got: " & tokKindToStr(p.tok.xkind))

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
  var info = getLineInfo(p.lex)
  info.line = p.tok.lineNumber.uint16
  result = newNodeI(kind, info)

proc newNumberNodeP(kind: TNodeKind, number: string, p: Parser): PNode =
  result = newNodeP(kind, p)
  result.strVal = number

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

include mangler

proc newBinary(opr: string, a, b: PNode, p: Parser): PNode =
  result = newNodeP(nkInfix, p)
  addSon(result, newIdentNodeP(getIdent(opr), p))
  addSon(result, a)
  addSon(result, b)

proc skipIdent(p: var Parser; kind: TSymKind, nest: bool = false): PNode =
  expectIdent(p)
  if nest and not p.currentClass.isNil and p.currentClass.kind == nkIdent:
    let name = p.currentClass.ident.s & p.tok.s
    result = mangledIdent(name, p, kind)
    p.options.toMangle[p.tok.s]= result.ident.s
  else:
    result = mangledIdent(p.tok.s, p, kind)
  getTok(p, result)

proc skipIdentExport(p: var Parser; kind: TSymKind, nest: bool = false): PNode =
  expectIdent(p)
  if nest and not p.currentClass.isNil and p.currentClass.kind == nkIdent:
    let name = p.currentClass.ident.s & p.tok.s
    let id = mangledIdent(name, p, kind)
    result = exportSym(p, id, p.tok.s)
    p.options.toMangle[p.tok.s]= id.ident.s
  else:
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

proc expression(p: var Parser, rbp: int = 0; parent: PNode = nil): PNode
proc constantExpression(p: var Parser; parent: PNode = nil): PNode = expression(p, 40, parent)
proc assignmentExpression(p: var Parser): PNode = expression(p, 30)
proc compoundStatement(p: var Parser; newScope=true): PNode
proc statement(p: var Parser): PNode
template initExpr(p: untyped): untyped = expression(p, 11)

proc declKeyword(p: Parser, s: string): bool =
  # returns true if it is a keyword that introduces a declaration
  case s
  of  "extern", "static", "auto", "register", "const", "volatile",
      "restrict", "inline", "__inline", "__cdecl", "__stdcall", "__syscall",
      "__fastcall", "__safecall", "void", "struct", "union", "enum", "typedef",
      "size_t", "short", "int", "long", "float", "double", "signed", "unsigned",
      "char", "__declspec", "__attribute__":
    result = true
  of "class", "mutable", "constexpr", "consteval", "constinit", "decltype":
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

proc skipConst(p: var Parser): bool =
  while p.tok.xkind == pxSymbol and
      (p.tok.s in ["const", "volatile", "restrict"] or
      (p.tok.s in ["mutable", "constexpr", "consteval", "constinit"] and pfCpp in p.options.flags)):
    if p.tok.s in ["const", "constexpr"]: result = true
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
      if angles > 1: dec(angles)
    of pxLt: inc(angles)
    of pxParRi, pxBracketRi, pxCurlyRi:
      let kind = pred(kind, 3)
      if i[kind] > 0: dec(i[kind])
      else: break
    of pxSemicolon, pxBarBar, pxAmpAmp: break
    else: discard
    getTok(p, nil)
  backtrackContext(p)

proc hasValue(t: StringTableRef, s: string): bool =
  for v in t.values:
    if v == s: return true

proc optScope(p: var Parser, n: PNode; kind: TSymKind): PNode =
  result = n
  if pfCpp in p.options.flags:
    while p.tok.xkind == pxScope:
      when false:
        getTok(p, result)
        expectIdent(p)
        result = mangledIdent(p.tok.s, p, kind)
      else:
        getTok(p, result)
        expectIdent(p)
        if n.kind == nkIdent:
          if p.options.classes.hasValue(n.ident.s):
            result = mangledIdent(n.ident.s & p.tok.s, p, kind)
          else:
            result = mangledIdent(p.tok.s, p, kind)
        elif n.kind == nkBracketExpr:
          if p.options.classes.hasValue(n[0].ident.s):
            result.sons[0] = mangledIdent(n[0].ident.s & p.tok.s, p, kind)
          else:
            result.sons[0] = mangledIdent(p.tok.s, p, kind)
      getTok(p, result)

proc parseTypeSuffix(p: var Parser, typ: PNode, isParam: bool = false): PNode
proc parseTemplateParamType(p: var Parser): PNode =
  result = typeDesc(p)
  result = parseTypeSuffix(p, result)

proc optAngle(p: var Parser, n: PNode): PNode =
  if p.tok.xkind == pxLt and isTemplateAngleBracket(p):
    getTok(p)
    if n.kind == nkBracketExpr:
      result = n
    else:
      result = newNodeP(nkBracketExpr, p)
      result.add(n.copyTree)
    inc p.inAngleBracket
    while true:
      let a = if p.tok.xkind == pxSymbol: parseTemplateParamType(p)
              else: assignmentExpression(p)
      if not a.isNil: result.add(a)
      if p.tok.xkind != pxComma: break
      getTok(p)
    dec p.inAngleBracket
    eat(p, pxAngleRi)
    result = optScope(p, result, skType)
  else:
    result = n

proc skipClassAfterEnum(p: var Parser, n: PNode) =
  if p.tok.xkind == pxSymbol and p.tok.s in ["struct", "class"] and pfCpp in p.options.flags:
    getTok(p, n)

proc typeAtom(p: var Parser; isTypeDef=false): PNode =
  var isConst = skipConst(p)
  expectIdent(p)
  case p.tok.s
  of "void":
    result = newNodeP(nkNilLit, p) # little hack
    getTok(p, nil)
  of "struct", "union":
    getTok(p, nil)
    result = skipIdent(p, skType)
  of "enum":
    getTok(p, nil)
    result = skipIdent(p, skType)
    skipClassAfterEnum(p, result)
  elif p.tok.s == "typeof" or (p.tok.s == "decltype" and pfCpp in p.options.flags):
    result = newNodeP(nkCall, p)
    result.add newIdentNodeP("typeof", p)
    getTok(p, result)
    eat(p, pxParLe, result)
    result.add expression(p)
    eat(p, pxParRi, result)
  elif isIntType(p.tok.s):
    var x = ""
    #getTok(p, nil)
    var isUnsigned = false
    var isSigned = false
    var isSizeT = false
    while p.tok.xkind == pxSymbol and (isIntType(p.tok.s) or p.tok.s == "char"):
      if p.tok.s == "unsigned":
        isUnsigned = true
      elif p.tok.s == "size_t":
        isSizeT = true
      elif p.tok.s == "signed":
        isSigned = true
      elif p.tok.s == "int":
        discard
      else:
        add(x, p.tok.s)
      getTok(p, nil)
      if (isSigned or isUnsigned) and p.tok.xkind == pxSymbol and isTypeDef:
        add(x, p.tok.s)
        getTok(p, nil)

      if skipConst(p): isConst = true
    if x.len == 0: x = "int"
    let xx = if isSizeT: "csize_t" elif isUnsigned: "cu" & x else: "c" & x
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

proc pointersOf(p: Parser; a: PNode; count: int): PNode =
  if count == 0:
    result = a
  elif a.kind == nkIdent and a.ident.s == "char":
    if count >= 2:
      result = newIdentNodeP("cstringArray", p)
      for j in 1..count-2: result = newPointerTy(p, result)
    elif count == 1: result = newIdentNodeP("cstring", p)
  elif a.kind == nkNilLit and count > 0:
    result = newIdentNodeP("pointer", p)
    for j in 1..count-1: result = newPointerTy(p, result)
  else:
    result = a
    for j in 1..count - ord(a.kind == nkProcTy):
      result = newPointerTy(p, result)

proc pointer(p: var Parser, a: PNode): PNode =
  result = a
  var i = 0
  let isConstA = skipConst(p)
  while true:
    if p.tok.xkind == pxStar:
      inc(i)
      getTok(p, result)
      discard skipConst(p)
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
      discard skipConst(p)
      if pfIgnoreRvalueRefs notin p.options.flags:
        let b = result
        result = newNodeP(nkVarTy, p)
        result.add(b)
    else: break
  if i > 0:
    result = pointersOf(p, a, i)

proc newProcPragmas(p: Parser): PNode =
  result = newNodeP(nkPragma, p)
  if pfCDecl in p.options.flags:
    addSon(result, newIdentNodeP("cdecl", p))
  elif pfStdCall in p.options.flags:
    addSon(result, newIdentNodeP("stdcall", p))
  elif pfNoConv in p.options.flags:
    addSon(result, newIdentNodeP("noconv", p))

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

proc parseTypeSuffix(p: var Parser, typ: PNode, isParam: bool = false): PNode =
  result = typ
  case p.tok.xkind
  of pxBracketLe:
    getTok(p, result)
    discard skipConst(p) # POSIX contains: ``int [restrict]``
    if p.tok.xkind != pxBracketRi:
      var tmp = result
      var index = expression(p)
      # array type:
      result = newNodeP(nkBracketExpr, p)
      if index.kind == nkIntLit and index.strVal == "0":
        addSon(result, newIdentNodeP("UncheckedArray", p))
      else:
        addSon(result, newIdentNodeP("array", p))
        addSon(result, index)
      eat(p, pxBracketRi, result)
      addSon(result, parseTypeSuffix(p, tmp))
    else:
      # pointer type:
      var tmp = result
      if pfRefs in p.options.flags:
        result = newNodeP(nkRefTy, p)
      elif isParam:
        result = newNodeP(nkPtrTy, p)
      else:
        # flexible array
        result = newNodeP(nkBracketExpr, p)
        addSon(result, newIdentNodeP("UncheckedArray", p))
      eat(p, pxBracketRi, result)
      addSon(result, parseTypeSuffix(p, tmp))
  of pxParLe:
    # function pointer:
    var procType = newNodeP(nkProcTy, p)
    var pragmas = newProcPragmas(p)
    var params = newNodeP(nkFormalParams, p)
    discard addReturnType(params, result)
    saveContextB(p)
    try:
      parseFormalParams(p, params, pragmas)
      closeContextB(p)

      addSon(procType, params)
      addPragmas(procType, pragmas)
      result = parseTypeSuffix(p, procType)

    except ERetryParsing:
      backtrackContextB(p)
      result = typ

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

proc parseField(p: var Parser, kind: TNodeKind; pointers: var int): PNode =
  if p.tok.xkind == pxParLe:
    getTok(p, nil)
    while p.tok.xkind == pxStar:
      getTok(p, nil)
      inc pointers
    result = parseField(p, kind, pointers)
    eat(p, pxParRi, result)
  else:
    expectIdent(p)
    if kind == nkRecList: result = fieldIdent(p.tok.s, p)
    else: result = mangledIdent(p.tok.s, p, skField)
    getTok(p, result)

proc cppImportName(p: Parser, origName: string,
                    genericParams: PNode = nil,
                    baseType: bool = false): string =
  let ast = if baseType: "*" else: ""
  var c = 0
  template addGenerics(cgp: PNode) =
    if cgp.kind == nkGenericParams:
      result &= "<"
      for i in 0..<cgp.len-1:
        result &= "'" & ast & $c & ","
        inc c
      result &= "'" & ast & $c & ">"
      inc c
  if p.classHierarchy.len > 0:
    result = p.currentNamespace & p.classHierarchy[0]
    addGenerics(p.classHierarchyGP[0])
    for i in 1..<p.classHierarchy.len:
      result &= "::" & p.classHierarchy[i]
      addGenerics(p.classHierarchyGP[i])
    if origName != "":
      result &= "::" & origName
  else:
    result = p.currentNamespace & origName
  if not genericParams.isNil:
    addGenerics(genericParams)

proc structPragmas(p: Parser, name: PNode, origName: string,
                   isUnion: bool; genericParams: PNode = nil): PNode =
  assert name.kind == nkIdent
  result = newNodeP(nkPragmaExpr, p)
  addSon(result, exportSym(p, name, origName))
  var pragmas = newNodeP(nkPragma, p)
  #addSon(pragmas, newIdentNodeP("pure", p), newIdentNodeP("final", p))
  if p.options.useHeader:
    let iname = cppImportName(p, origName, genericParams)
    addSon(pragmas,
      newIdentStrLitPair(p.options.importcLit, iname, p),
      getHeaderPair(p))
  if p.options.inheritable.hasKey(origName):
    addSon(pragmas, newIdentNodeP("inheritable", p))
    addSon(pragmas, newIdentNodeP("pure", p))
  pragmas.add newIdentNodeP("bycopy", p)
  if isUnion: pragmas.add newIdentNodeP("union", p)
  result.add pragmas

proc hashPosition(p: var Parser): string =
  let lineInfo = parLineInfo(p)
  when declared(gConfig):
    let fileInfo = toFilename(gConfig, lineInfo.fileIndex).splitFile.name
  else:
    let fileInfo = toFilename(lineInfo.fileIndex).splitFile.name
  result = fileInfo & "_" & $p.anoTypeCount
  inc(p.anoTypeCount)

proc parseInnerStruct(p: var Parser, stmtList: PNode,
                      isUnion: bool, name: string): PNode =
  if p.tok.xkind != pxCurlyLe:
    parError(p, "Expected '{' but found '" & $(p.tok[]) & "'")

  var structName: string
  if name == "":
    if isUnion: structName = "INNER_C_UNION_" & p.hashPosition
    else: structName = "INNER_C_STRUCT_" & p.hashPosition
  else:
    structName = name & "_" & p.hashPosition
  let typeSection = newNodeP(nkTypeSection, p)
  let newStruct = newNodeP(nkObjectTy, p)
  addSon(newStruct, emptyNode, emptyNode) # no pragmas, no inheritance
  result = newNodeP(nkIdent, p)
  result.ident = getIdent(structName)
  let struct = parseStructBody(p, stmtList)
  let defName = newNodeP(nkIdent, p)
  defName.ident = getIdent(structName)
  addSon(newStruct, struct)
  addTypeDef(typeSection, structPragmas(p, defName, "no_name", isUnion),
             newStruct, emptyNode)
  addSon(stmtList, typeSection)

proc parseBitfield(p: var Parser, i: PNode): PNode =
  if p.tok.xkind == pxColon:
    getTok(p)
    var bits = p.tok.s
    eat(p, pxIntLit)
    var bitsize = newNodeP(nkExprColonExpr, p)
    addSon(bitsize, newIdentNodeP("bitsize", p))
    addSon(bitsize, newNumberNodeP(nkIntLit, bits, p))
    if i.kind == nkPragmaExpr:
      result = i
      addSon(result[1], bitsize)
    else:
      var pragma = newNodeP(nkPragma, p)
      addSon(pragma, bitsize)
      result = newNodeP(nkPragmaExpr, p)
      addSon(result, i)
      addSon(result, pragma)
  else:
    result = i

import compiler/nimlexbase

proc parseStructBody(p: var Parser, stmtList: PNode,
                     kind: TNodeKind = nkRecList): PNode =
  result = newNodeP(kind, p)
  let com = newNodeP(nkCommentStmt, p)
  eat(p, pxCurlyLe, com)
  if com.comment.len() > 0:
    addSon(result, com)
  while p.tok.xkind notin {pxEof, pxCurlyRi}:
    let ln = p.parLineInfo().line
    if p.tok.xkind in {pxLineComment, pxStarComment}:
      let com = newNodeP(nkCommentStmt, p)
      com.info.line = p.tok.lineNumber.uint16
      addSon(result, com)
      skipComAux(p, com)
      continue
    discard skipConst(p)
    var baseTyp: PNode
    if p.tok.xkind == pxSymbol and p.tok.s in ["struct", "union"]:
      let gotUnion = if p.tok.s == "union": true else: false
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
      if p.tok.xkind == pxSymbol:
        baseTyp = typeAtom(p)
      else:
        continue
    else:
      baseTyp = typeAtom(p)

    while true:
      var def = newNodeP(nkIdentDefs, p)
      var t = pointer(p, baseTyp)
      var fieldPointers = 0
      var i = parseField(p, kind, fieldPointers)
      t = pointersOf(p, parseTypeSuffix(p, t), fieldPointers)
      i = parseBitfield(p, i)
      addSon(def, i, t, emptyNode)
      addSon(result, def)
      if p.tok.xkind != pxComma: break
      getTok(p, def)

    eat(p, pxSemicolon)

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
    var hasGeneric = false
    for a in p.classHierarchyGP:
      if a.kind != nkEmpty:
        hasGeneric = true
        break
    if not hasGeneric:
      let importName = cppImportName(p, origName)
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

proc parseStruct(p: var Parser, stmtList: PNode): PNode =
  result = newNodeP(nkObjectTy, p)
  var pragmas = emptyNode
  addSon(result, pragmas, emptyNode) # no inheritance
  parseInheritance(p, result)
  # 'struct foo;' or 'union foo;' <- forward declaration; in order to avoid
  # multiple definitions, we ignore those completely:
  if p.tok.xkind == pxSemicolon:
    eat(p, pxSemicolon, result)
    return nil
  if p.tok.xkind == pxCurlyLe:
    addSon(result, parseStructBody(p, stmtList))
  else:
    addSon(result, newNodeP(nkRecList, p))

proc declarator(p: var Parser, a: PNode, ident: ptr PNode; origName: var string): PNode

proc directDeclarator(p: var Parser, a: PNode, ident: ptr PNode; origName: var string): PNode =
  case p.tok.xkind
  of pxSymbol:
    origName = p.tok.s
    ident[] = skipIdent(p, skParam)
  of pxParLe:
    getTok(p, a)
    if p.tok.xkind in {pxStar, pxAmp, pxAmpAmp, pxSymbol}:
      result = declarator(p, a, ident, origName)
      eat(p, pxParRi, result)
  else:
    discard
  result = parseTypeSuffix(p, a, true)

proc declarator(p: var Parser, a: PNode, ident: ptr PNode; origName: var string): PNode =
  directDeclarator(p, pointer(p, a), ident, origName)

proc makeUncheckedArray(p: Parser; t: PNode): PNode =
  assert t.kind == nkPtrTy
  result = newTree(nkPtrTy,
    newTree(nkBracketExpr,
      newIdentNodeP("UncheckedArray", p), t[0]))

# parameter-declaration
#   declaration-specifiers declarator
#   declaration-specifiers asbtract-declarator(opt)
proc parseParam(p: var Parser, params: PNode) =
  var typ = typeDesc(p)
  # support for ``(void)`` parameter list:
  if typ.kind == nkNilLit and p.tok.xkind == pxParRi: return
  var name: PNode
  var origName = ""
  typ = declarator(p, typ, addr name, origName)
  if name == nil:
    var idx = sonsLen(params)
    name = newIdentNodeP(p.options.paramPrefix & $idx, p)
  elif p.options.isArray.hasKey(origName) and typ.kind == nkPtrTy:
    typ = makeUncheckedArray(p, typ)

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
  if p.tok.xkind == pxArrow and pfCpp in p.options.flags:
    getTok(p, params)
    params[0] = typeDesc(p)

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
    of "__declspec":
      getTok(p, nil)
      eat(p, pxParLe, nil)
      while p.tok.xkind notin {pxEof, pxParRi}: getTok(p, nil)
    of "__attribute__":
      getTok(p, nil)
      eat(p, pxParLe, nil)
      while p.tok.xkind notin {pxEof, pxParRi}: getTok(p, nil)
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
  #else: parError(p, "expected '*'")
  if p.inTypeDef > 0: markTypeIdent(p, nil)
  var name = skipIdentExport(p, if p.inTypeDef > 0: skType else: skVar, true)
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

proc findGenericParam(g: PNode, n: PNode): bool

proc otherTypeDef(p: var Parser, section, typ: PNode) =
  var gp = emptyNode
  let genericParams = inheritedGenericParams(p)
  if findGenericParam(genericParams, typ):
    gp = newNodeP(nkGenericParams, p)
    gp.add(typ)
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
    name = skipIdentExport(p, skType, true)
  t = parseTypeSuffix(p, t)
  addTypeDef(section, name, t, gp)

proc parseTrailingDefinedTypes(p: var Parser, section, typ: PNode) =
  while p.tok.xkind == pxComma:
    getTok(p, nil)
    var newTyp = pointer(p, typ)
    markTypeIdent(p, newTyp)
    var newName = skipIdentExport(p, skType, true)
    newTyp = parseTypeSuffix(p, newTyp)
    addTypeDef(section, newName, newTyp, emptyNode)

proc createConst(name, typ, val: PNode, p: Parser): PNode =
  result = newNodeP(nkConstDef, p)
  addSon(result, name, typ, val)

proc extractNumber(s: string): tuple[succ: bool, val: BiggestInt] =
  try:
    if s.startsWith("0x"):
      result = (true, fromHex[BiggestInt](s))
    elif s.startsWith("0o"):
      result = (true, fromOct[BiggestInt](s))
    elif s.startsWith("0b"):
      result = (true, fromBin[BiggestInt](s))
    else:
      result = (true, parseBiggestInt(s))
  except ValueError:
    result = (false, 0'i64)

proc exprToNumber(n: PNode): tuple[succ: bool, val: BiggestInt] =
  result = (false, 0.BiggestInt)
  case n.kind:
  of nkPrefix:
    # Check for negative/positive numbers  -3  or  +6
    if n.sons.len == 2 and n.sons[0].kind == nkIdent and n.sons[1].kind == nkIntLit:
      let pre = n.sons[0]
      let num = n.sons[1]
      if pre.ident.s == "-":
        result = extractNumber("-" & num.strVal)
      elif pre.ident.s == "+":
        result = extractNumber(num.strVal)
  of nkIntLit..nkUInt64Lit:
    result = extractNumber(n.strVal)
  of nkCharLit:
    result = (true, BiggestInt n.strVal[0])
  else: discard

template any(x, cond: untyped): untyped =
  var result = false
  for it {.inject.} in x:
    if cond: result = true; break
  result

proc getEnumIdent(n: PNode): PNode =
  if n.kind == nkEnumFieldDef: result = n[0]
  else: result = n
  assert result.kind == nkIdent

proc buildStmtList(a: PNode): PNode

include preprocessor

proc enumFields(p: var Parser, constList, stmtList: PNode): PNode =
  type EnumFieldKind = enum isNormal, isNumber, isAlias
  result = newNodeP(nkEnumTy, p)
  addSon(result, emptyNode) # enum does not inherit from anything
  var i: BiggestInt = 0
  var field: tuple[id: BiggestInt, kind: EnumFieldKind, node, value: PNode]
  var fields = newSeq[type(field)]()
  var fieldsComplete = false
  while p.tok.xkind != pxCurlyRi:
    if p.tok.xkind == pxDirective or p.tok.xkind == pxDirectiveParLe:
      var define = parseDir(p, statement)
      addSon(stmtList, define)
      continue

    if fieldsComplete: parError(p, "expected '}'")
    var e = skipIdent(p, skEnumField)
    if p.tok.xkind == pxAsgn:
      getTok(p, e)
      var c = constantExpression(p, e)
      var a = e
      e = newNodeP(nkEnumFieldDef, p)
      addSon(e, a, c)
      skipCom(p, e)
      field.value = c
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
    if p.tok.xkind == pxComma: getTok(p, e)
    else: fieldsComplete = true
  if fields.len == 0: parError(p, "enum has no fields")
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
          else: parError(p, outofOrder)
        of nkIdent: currentIdent = f.node
        else: parError(p, outofOrder)
        var constant = createConst(currentIdent, emptyNode, lastIdent, p)
        constList.addSon(constant)
      else:
        addSon(result, f.node)
        lastId = f.id
        case f.node.kind:
        of nkEnumFieldDef:
          if f.node.sons.len > 0 and f.node.sons[0].kind == nkIdent:
            lastIdent = f.node.sons[0]
          else: parError(p, outofOrder)
        of nkIdent: lastIdent = f.node
        else: parError(p, outofOrder)
    of isAlias:
      let ident = f.node.getEnumIdent
      var constant = createConst(exportSym(p, ident, ident.ident.s), emptyNode,
                                 f.value, p)
      constList.addSon(constant)


proc parseTypedefStruct(p: var Parser, result, stmtList: PNode,
                        isUnion, isStruct: bool) =
  template parseStruct(res, name: PNode, origName: string,
                        stmtList, gp: PNode) =
    oldClass = p.currentClass
    oldClassOrig = p.currentClassOrig
    p.currentClass = name
    p.currentClassOrig = origName
    deepCopy(oldToMangle, p.options.toMangle)
    p.classHierarchy.add(origName)
    p.classHierarchyGP.add(gp)
    res = if isUnion or (isStruct and not (pfCpp in p.options.flags)):
            parseStruct(p, stmtList)
          else:
            parseClass(p, isStruct, stmtList, genericParams)
    p.currentClass = oldClass
    p.currentClassOrig = oldClassOrig
    p.options.toMangle = oldToMangle
    discard p.classHierarchy.pop()
    discard p.classHierarchyGP.pop()

  let genericParams = inheritedGenericParams(p)
  var
    oldClass, t: PNode
    oldClassOrig: string
    oldToMangle: StringTableRef
  getTok(p, result)
  if p.tok.xkind == pxCurlyLe:
    saveContext(p)
    var tstmtList = newNodeP(nkStmtList, p)
    if isUnion or (isStruct and not (pfCpp in p.options.flags)):
      discard parseStruct(p, tstmtList)
    else:
      discard parseClass(p, isStruct,  tstmtList, genericParams)
    var origName = p.tok.s
    markTypeIdent(p, nil)
    var name = skipIdent(p, skType, true)
    backtrackContext(p)
    parseStruct(t, name, origName, stmtList, emptyNode)
    getTok(p)
    addTypeDef(result, structPragmas(p, name, origName, isUnion), t, genericParams)
    p.options.classes[origName] = name.ident.s
    parseTrailingDefinedTypes(p, result, name)
  elif p.tok.xkind == pxSymbol:
    # name to be defined or type "struct a", we don't know yet:
    markTypeIdent(p, nil)
    var origName = p.tok.s
    var nameOrType = skipIdent(p, skVar)
    case p.tok.xkind
    of pxCurlyLe:
      saveContext(p)
      var id: PNode
      if not p.currentClass.isNil and p.currentClass.kind == nkIdent:
        id = mangledIdent(p.currentClass.ident.s & origName, p, skType)
        p.options.toMangle[origName] = id.ident.s
      else:
        id = mangledIdent(origName, p, skType)
      var tstmtList = newNodeP(nkStmtList, p)
      parseStruct(t, id, origName, tstmtList, emptyNode)
      if p.tok.xkind == pxSymbol:
        # typedef struct tagABC {} abc, *pabc;
        # --> abc is a better type name than tagABC!
        markTypeIdent(p, nil)
        var origName = p.tok.s
        var name = skipIdent(p, skType, true)
        backtrackContext(p)
        parseStruct(t, name, origName, stmtList, emptyNode)
        getTok(p)
        addTypeDef(result, structPragmas(p, name, origName, isUnion), t, genericParams)
        p.options.classes[origName] = name.ident.s
        parseTrailingDefinedTypes(p, result, name)
      else:
        for a in tstmtList:
          stmtList.add(a)
        addTypeDef(result, structPragmas(p, nameOrType, origName, isUnion), t,
                   genericParams)
        p.options.classes[origName] = nameOrType.ident.s
    of pxSymbol:
      # typedef struct a a?
      if pfStructStruct in p.options.flags:
        let nn = mangledIdent(p.tok.s, p, skType)
        getTok(p, nil)
        markTypeIdent(p, nn)
        let t = newNodeP(nkObjectTy, p)
        addSon(t, emptyNode, emptyNode) # no pragmas, no inheritance
        addSon(t, newNodeP(nkRecList, p))
        addTypeDef(result, nn, t, emptyNode)
      elif mangleName(p.tok.s, p, skType) == nameOrType.ident.s:
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

proc parseTypedefEnum(p: var Parser, result, constSection, stmtList: PNode) =
  getTok(p, result)
  skipClassAfterEnum(p, result)
  if p.tok.xkind == pxCurlyLe:
    getTok(p, result)
    var t = enumFields(p, constSection, stmtList)
    eat(p, pxCurlyRi, t)
    var origName = p.tok.s
    markTypeIdent(p, nil)
    var name = skipIdent(p, skType, true)
    addTypeDef(result, enumPragmas(p, exportSym(p, name, origName), origName),
               t, emptyNode)
    parseTrailingDefinedTypes(p, result, name)
  elif p.tok.xkind == pxSymbol:
    # name to be defined or type "enum a", we don't know yet:
    markTypeIdent(p, nil)
    var origName = p.tok.s
    var nameOrType = skipIdent(p, skType, true)
    case p.tok.xkind
    of pxCurlyLe:
      getTok(p, result)
      var t = enumFields(p, constSection, stmtList)
      eat(p, pxCurlyRi, t)
      if p.tok.xkind == pxSymbol:
        # typedef enum tagABC {} abc, *pabc;
        # --> abc is a better type name than tagABC!
        markTypeIdent(p, nil)
        var origName = p.tok.s
        var name = skipIdent(p, skType, true)
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

proc findGenericParam(g: PNode, n: PNode): bool =
  if n.kind == nkIdent:
    for a in g:
      if a.len > 0 and a[0].kind == nkIdent and a[0].ident.s == n.ident.s:
        return true

proc inheritedGenericParams(p: Parser) : PNode =
  if p.classHierarchyGP.len > 0:
    result = newNodeP(nkGenericParams, p)
    for a in p.classHierarchyGP:
      if a.kind != nkGenericParams: continue
      for b in a:
        result.add(b)
    if result.len < 1:
      result = emptyNode
  else:
    result = emptyNode

proc parseTypename(p: var Parser, result: PNode) =
  getTok(p) #skip "typename"
  let t = typeAtom(p)
  let genericParams = inheritedGenericParams(p)
  var gpl = emptyNode
  if genericParams.kind != nkEmpty:
    gpl = newNodeP(nkGenericParams, p)
    if t.kind == nkBracketExpr:
      for i in 1..<t.len:
        if t[i].kind == nkIdent and findGenericParam(genericParams, t.sons[i]):
          gpl.add(t.sons[i])
    if gpl.len < 1: gpl = emptyNode
  let lname = skipIdentExport(p, skType, true)
  addTypeDef(result, lname, t, gpl)

proc parseTypeBody(p: var Parser; result, typeSection, afterStatements: PNode) =
  inc(p.inTypeDef)
  expectIdent(p)
  case p.tok.s
  of "struct": parseTypedefStruct(p, typeSection, result, isUnion=false, isStruct=true)
  of "union": parseTypedefStruct(p, typeSection, result, isUnion=true, isStruct=false)
  of "enum":
    var constSection = newNodeP(nkConstSection, p)
    parseTypedefEnum(p, typeSection, constSection, afterStatements)
    addSon(afterStatements, constSection)
  of "class":
    if pfCpp in p.options.flags:
      parseTypedefStruct(p, typeSection, result, isUnion=false, isStruct=false)
    else:
      var t = typeAtom(p, true)
      otherTypeDef(p, typeSection, t)
  of "typename":
    if pfCpp in p.options.flags:
      parseTypename(p, typeSection)
    else:
      var t = typeAtom(p, true)
      otherTypeDef(p, typeSection, t)
  else:
    var t = typeAtom(p, true)
    otherTypeDef(p, typeSection, t)
  eat(p, pxSemicolon)
  dec(p.inTypeDef)

proc parseTypeDef(p: var Parser): PNode =
  result = newNodeP(nkStmtList, p)
  var typeSection = newNodeP(nkTypeSection, p)
  var afterStatements = newNodeP(nkStmtList, p)
  while p.tok.xkind == pxSymbol and p.tok.s == "typedef":
    getTok(p, typeSection)
    parseTypeBody(p, result, typeSection, afterStatements)

  addSon(result, typeSection)
  for s in afterStatements:
    addSon(result, s)

proc skipDeclarationSpecifiers(p: var Parser; varKind: var TNodeKind) =
  while p.tok.xkind == pxSymbol:
    case p.tok.s
    of "const":
      getTok(p, nil)
      varKind = nkLetSection
    of "static", "register", "volatile":
      getTok(p, nil)
    of "auto":
      if pfCpp notin p.options.flags: getTok(p, nil)
      else: break
    of "constexpr", "consteval", "constinit":
      if pfCpp in p.options.flags:
        getTok(p, nil)
        if p.options.useHeader:
          varKind = nkLetSection
        else:
          varKind = nkConstSection
      else:
        break
    of "mutable":
      if pfCpp in p.options.flags: getTok(p, nil)
      else: break
    of "extern":
      getTok(p, nil)
      # extern "C" ?
      if pfCpp in p.options.flags and p.tok.xkind == pxStrLit and p.tok.s == "C":
        getTok(p, nil)
    else: break

proc skipThrowSpecifier(p: var Parser; pragmas: PNode) =
  if pfCpp notin p.options.flags: return
  while true:
    case p.tok.xkind
    of pxSymbol:
      case p.tok.s
      of "throw":
        getTok(p)
        var pms = newNodeP(nkFormalParams, p)
        var pgms = newNodeP(nkPragma, p)
        parseFormalParams(p, pms, pgms) #ignore
      of "noexcept":
        getTok(p)
        if p.tok.xkind == pxParLe:
          getTok(p)
          discard expression(p)
          eat(p, pxParRi)
        else:
          pragmas.add(newTree(nkExprColonExpr, newIdentNodeP("raises", p), newTree(nkBracket)))
      of "override", "final":
        getTok(p)
      else:
        break
    of pxAmp, pxAmpAmp:
      # ref qualifiers, see http://www.open-std.org/jtc1/sc22/wg21/docs/papers/2007/n2439.htm
      getTok(p)
    else:
      break

proc parseInitializer(p: var Parser; kind: TNodeKind; isArray: var bool): PNode =
  case p.tok.xkind
  of pxCurlyLe:
    result = newNodeP(kind, p)
    getTok(p, result)
    var isArray = false
    while p.tok.xkind notin {pxEof, pxCurlyRi}:
      addSon(result, parseInitializer(p, kind, isArray))
      opt(p, pxComma, nil)
    eat(p, pxCurlyRi, result)
    if isArray: result.kind = nkBracket
  of pxDot:
    # designated initializer?
    result = newNodeP(nkExprColonExpr, p)
    getTok(p)
    result.add skipIdent(p, skField)
    opt(p, pxAsgn, result[^1])
    result.add initExpr(p)
  of pxBracketLe:
    # designated initializer?
    if pfCpp notin p.options.flags:
      result = newNodeP(nkExprColonExpr, p)
      getTok(p)
      result.add initExpr(p)
      eat(p, pxBracketRi)
      opt(p, pxAsgn, result[^1])
      result.add initExpr(p)
      isArray = true
    else:
      result = initExpr(p)
  else:
    result = initExpr(p)

template discardVarParam(t): untyped = (var hidden: t; hidden)

proc addInitializer(p: var Parser, def: PNode) =
  if p.tok.xkind == pxAsgn:
    getTok(p, def)
    let initVal = parseInitializer(p, nkBracket, discardVarParam(bool))
    if p.options.dynlibSym.len > 0 or p.options.useHeader:
      addSon(def, emptyNode)
    else:
      addSon(def, initVal)
  elif p.tok.xkind == pxCurlyLe and pfCpp in p.options.flags:
    # C++11 initializer:  Foo x{1, 2, 3};
    # we transform it into:  var x = Foo(1, 2, 3)
    # for the lack of a better solution.
    let initVal = parseInitializer(p, nkTupleConstr, discardVarParam(bool))
    var constructorCall = newNodeI(nkCall, initVal.info)
    constructorCall.add copyTree(def[^1])
    for i in 0..<initVal.len:
      constructorCall.add initVal[i]
    if p.options.useHeader:
      # for headers we ignore initializer lists:
      addSon(def, emptyNode)
    else:
      addSon(def, constructorCall)
  elif p.tok.xkind == pxParLe and pfCpp in p.options.flags:
    var constructorCall = newNodeP(nkCall, p)
    constructorCall.add copyTree(def[^1])
    getTok(p, constructorCall)
    while p.tok.xkind notin {pxEof, pxParRi}:
      addSon(constructorCall, initExpr(p))
      opt(p, pxComma, nil)
    eat(p, pxParRi, constructorCall)

    if p.options.useHeader:
      # for headers we ignore initializer lists:
      addSon(def, emptyNode)
    else:
      addSon(def, constructorCall)
  else:
    addSon(def, emptyNode)

proc optInitializer(p: var Parser; n: PNode): PNode =
  if pfCpp in p.options.flags and p.tok.xkind == pxCurlyLe:
    let initVal = parseInitializer(p, nkTupleConstr, discardVarParam(bool))
    result = newNodeI(nkCall, initVal.info)
    result.add n
    for i in 0..<initVal.len:
      result.add initVal[i]
  else:
    result = n

proc parseVarDecl(p: var Parser, baseTyp, typ: PNode,
                  origName: string; varKind: TNodeKind): PNode =
  result = newNodeP(varKind, p)
  var def = newNodeP(nkIdentDefs, p)
  addSon(def, varIdent(origName, p, varKind))
  addSon(def, parseTypeSuffix(p, typ))
  addInitializer(p, def)
  addSon(result, def)

  while p.tok.xkind == pxComma:
    getTok(p, def)
    var t = pointer(p, baseTyp)
    expectIdent(p)
    def = newNodeP(nkIdentDefs, p)
    addSon(def, varIdent(p.tok.s, p, varKind))
    getTok(p, def)
    addSon(def, parseTypeSuffix(p, t))
    addInitializer(p, def)
    addSon(result, def)

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
        parError(p, "operator symbol expected")
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
    parError(p, "operator symbol expected")

when false:
  proc declarationName(p: var Parser): string =
    while p.tok.xkind == pxScope and pfCpp in p.options.flags:
      getTok(p) # skip "::"
      expectIdent(p)
      result.add("::")
      result.add(p.tok.s)
      getTok(p)

proc parseMethod(p: var Parser, origName: string, rettyp, pragmas: PNode,
                 isStatic, isOperator: bool;
                 genericParams, genericParamsThis: PNode): PNode

proc declarationWithoutSemicolon(p: var Parser; genericParams: PNode = emptyNode): PNode =
  result = newNodeP(nkProcDef, p)
  var pragmas = newNodeP(nkPragma, p)

  var varKind = nkVarSection
  skipDeclarationSpecifiers(p, varKind)
  parseCallConv(p, pragmas)
  skipDeclarationSpecifiers(p, varKind)
  expectIdent(p)
  var baseTyp = typeAtom(p)
  var rettyp = pointer(p, baseTyp)
  skipDeclarationSpecifiers(p, varKind)
  parseCallConv(p, pragmas)
  skipDeclarationSpecifiers(p, varKind)

  if p.tok.xkind == pxParLe:
    # Function pointer declaration: This is of course only a heuristic, but the
    # best we can do here.
    return parseFunctionPointerDecl(p, rettyp)

  expectIdent(p)
  var origName = p.tok.s
  if pfCpp in p.options.flags and p.tok.s == "operator":
    origName = ""
    var isConverter = parseOperator(p, origName)
    result = parseMethod(p, origName, rettyp, pragmas, true, true,
                         emptyNode, emptyNode)
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
    saveContextB(p)

    var name = mangledIdent(origName, p, skProc)
    var params = newNodeP(nkFormalParams, p)
    if addReturnType(params, rettyp):
      addDiscardable(origName, pragmas, p)
    # unless it isn't, bug #146: std::vector<int64_t> foo(10);
    try:
      parseFormalParams(p, params, pragmas)
      closeContextB(p)
    except ERetryParsing:
      backtrackContextB(p)
      return parseVarDecl(p, baseTyp, rettyp, origName, varKind)

    if pfCpp in p.options.flags and p.tok.xkind == pxSymbol and
        p.tok.s == "const":
      addSon(pragmas, newIdentNodeP("noSideEffect", p))
      getTok(p)
    if pfCDecl in p.options.flags:
      addSon(pragmas, newIdentNodeP("cdecl", p))
    elif pfStdcall in p.options.flags:
      addSon(pragmas, newIdentNodeP("stdcall", p))
    if pfImportc in p.options.flags:
      addSon(pragmas, newIdentStrLitPair(p.options.importcLit, origName, p))
    # no pattern, no exceptions:
    addSon(result, exportSym(p, name, origName), emptyNode, genericParams)
    addSon(result, params, pragmas, emptyNode) # no exceptions
    skipThrowSpecifier(p, pragmas)
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
      parError(p, "expected ';'")
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
                         isStatic, false, emptyNode, emptyNode)
    if not isStatic:
      p.currentClass = oldClass
      p.currentClassOrig = oldClassOrig

  else:
    result = parseVarDecl(p, baseTyp, rettyp, origName, varKind)
  assert result != nil

proc declaration(p: var Parser; genericParams: PNode = emptyNode): PNode =
  result = declarationWithoutSemicolon(p, genericParams)
  if result.kind != nkProcDef:
    eat(p, pxSemicolon)

proc enumSpecifier(p: var Parser; stmtList: PNode): PNode =
  saveContext(p)
  getTok(p, nil) # skip "enum"
  skipClassAfterEnum(p, nil)
  case p.tok.xkind
  of pxCurlyLe:
    closeContext(p)
    # make a const section out of it:
    result = newNodeP(nkConstSection, p)
    getTok(p, result)
    var i = 0
    var hasUnknown = false
    var fieldsComplete = false
    while p.tok.xkind != pxCurlyRi:
      if isDir(p, "define"):
        skipLine(p)
        continue
      if fieldsComplete: parError(p, "expected '}'")
      var origName = p.tok.s
      var name = skipIdentExport(p, skEnumField, true)
      var val: PNode
      if p.tok.xkind == pxAsgn:
        getTok(p, name)
        val = constantExpression(p)
        hasUnknown = true
        if val.kind == nkIntLit:
          let (ok, ii) = extractNumber(val.strVal)
          if ok:
            i = int(ii)+1
            hasUnknown = false
      else:
        if hasUnknown:
          parMessage(p, warnUser, "computed const value may be wrong: " &
            name.renderTree)
        val = newNumberNodeP(nkIntLit, $i, p)
        inc(i)
      var c = createConst(name, emptyNode, val, p)
      p.options.toMangle[origName] = name[1].ident.s
      addSon(result, c)
      if p.tok.xkind == pxComma: getTok(p, c)
      else: fieldsComplete = true
    if result.sons.len == 0: parError(p, "enum has no fields")
    eat(p, pxCurlyRi, result)
    eat(p, pxSemicolon)
  of pxSymbol:
    var origName = p.tok.s
    markTypeIdent(p, nil)
    result = skipIdent(p, skType, true)
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
      var e = enumFields(p, constSection, stmtList)
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
    parError(p, "expected '{'")
    result = emptyNode

when false:
  proc looksLikeLambda(p: var Parser): bool =
    proc skipToParEnd(p: var Parser; closePar: Tokkind): bool =
      var counter = 0
      result = false
      while p.tok.xkind != pxEof:
        if p.tok.xkind == correspondingOpenPar(closePar):
          inc counter
        elif p.tok.xkind == closePar:
          if counter == 0:
            result = true
            getTok(p)
            break
        else: discard
        getTok(p)

    saveContext(p)

    # note: '[' token already skipped here.
    if skipToParEnd(p, pxBracketRi):
      if p.tok.xkind == pxParLe:
        getTok(p)
        if skipToParEnd(p, pxParRi):
          if p.tok.xkind == pxArrow:
            getTok(p)
            discard typeDesc(p)
          result = p.tok.xkind == pxCurlyLe
      else:
        result = p.tok.xkind == pxCurlyLe
    closeContext(p)

proc parseLambda(p: var Parser): PNode =
  result = newNodeP(nkLambda, p)

  # note: '[' token already skipped here.
  while p.tok.xkind notin {pxEof, pxBracketRi}: getTok(p)
  eat(p, pxBracketRi, result)

  var pragmas = newProcPragmas(p)
  var params = newNodeP(nkFormalParams, p)
  discard addReturnType(params, newIdentNodeP("auto", p))
  if p.tok.xkind == pxParLe:
    # C++23: parameter list is entirely optional
    parseFormalParams(p, params, pragmas)
  elif p.tok.xkind == pxArrow:
    params[0] = typeDesc(p)

  while p.tok.xkind == pxSymbol and p.tok.s in ["mutable", "constexpr", "consteval", "noexcept"]:
    getTok(p, result)

  let body = compoundStatement(p)
  addSon(result, emptyNode, emptyNode, emptyNode)
  if pragmas.len == 0:
    pragmas = newNodeP(nkEmpty, p)
  addSon(result, params, pragmas, emptyNode) # no exceptions
  addSon(result, body)

# Expressions

proc setBaseFlags(n: PNode, base: NumericalBase) =
  case base
  of base10: discard
  of base2: incl(n.flags, nfBase2)
  of base8: incl(n.flags, nfBase8)
  of base16: incl(n.flags, nfBase16)

proc endsWithIgnoreCase(s: string; suffix: string): bool =
  if s.len < suffix.len: return false
  for i in 0..<suffix.len:
    if toLowerAscii(s[s.len - suffix.len + i]) != toLowerAscii(suffix[i]): return false
  return true

proc translateNumber(s: string; p: var Parser): PNode =
  template t(s, suffix, nimSuffix) =
    if s.endsWithIgnoreCase(suffix):
      return newNumberNodeP(nkIntLit, s[0..^(suffix.len+1)] & nimSuffix, p)

  if s[^1] in {'A'..'Z', 'a'..'z'}:
    t(s, "ull", "'u64")
    t(s, "ul", "'u32")
    t(s, "u", "'u")
    t(s, "ll", "'i64")
    t(s, "l", "'i32")
    if s.startsWith("0x") or s.startsWith("0X"):
      result = newNumberNodeP(nkIntLit, s & "'u", p)
    else:
      result = newNumberNodeP(nkIntLit, s, p)
  else:
    if s.startsWith("0x") or s.startsWith("0X"):
      result = newNumberNodeP(nkIntLit, s & "'u", p)
    else:
      result = newNumberNodeP(nkInt64Lit, s, p)

proc startExpression(p: var Parser, tok: Token): PNode =
  case tok.xkind
  of pxSymbol:
    if tok.s == "NULL":
      result = newNodeP(nkNilLit, p)
    elif tok.s == "nullptr" and pfCpp in p.options.flags:
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
    elif p.inPreprocessorExpr > 0 and tok.s == "defined":
      result = newNodeP(nkCall, p)
      addSon(result, newIdentNodeP(tok.s, p))
      if p.tok.xkind == pxParLe:
        getTok(p, result)
        addSon(result, skipIdent(p, skConditional))
        eat(p, pxParRi, result)
      else:
        addSon(result, skipIdent(p, skConditional))
    else:
      let kind = if p.inAngleBracket > 0: skType else: skProc
      if kind == skProc and p.options.classes.hasKey(tok.s):
        result = mangledIdent(p.options.constructor & tok.s, p, kind)
      else:
        result = mangledIdent(tok.s, p, kind)
      result = optScope(p, result, kind)
      result = optAngle(p, result)
      result = optInitializer(p, result)
  of pxIntLit:
    result = newNumberNodeP(nkIntLit, tok.s, p)
    setBaseFlags(result, tok.base)
  of pxInt64Lit:
    result = translateNumber(tok.s, p)
    setBaseFlags(result, tok.base)
  of pxFloatLit:
    result = newNumberNodeP(nkFloatLit, tok.s, p)
    setBaseFlags(result, tok.base)
  of pxStrLit:
    result = newStrNodeP(nkStrLit, tok.s, p)
    while p.tok.xkind == pxStrLit:
      add(result.strVal, p.tok.s)
      getTok(p, result)
  of pxCharLit:
    result = newNumberNodeP(nkCharLit, tok.s, p)
  of pxParLe:
    try:
      saveContext(p)
      result = newNodeP(nkPar, p)
      addSon(result, expression(p, 0))
      if p.tok.xkind != pxParRi:
        raise newException(ERetryParsing, "expected a ')'")
      getTok(p, result)
      if p.tok.xkind in {pxSymbol, pxIntLit, pxInt64Lit, pxFloatLit, pxStrLit, pxCharLit}:
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
  of pxToString:
    result = newNodeP(nkCall, p)
    addSon(result, newIdentNodeP("astToStr", p))
    addSon(result, newIdentNodeP(tok.s, p))
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
  of pxCurlyLe:
    result = newNodeP(nkTupleConstr, p)
    var isArray = false
    while p.tok.xkind notin {pxEof, pxCurlyRi}:
      result.add parseInitializer(p, nkBracket, isArray)
      # addSon(result, expression(p, 11)) # XXX
      if p.tok.xkind == pxComma: getTok(p, result[^1])
    eat(p, pxCurlyRi)
    if isArray: result.kind = nkBracket
  of pxBracketLe:
    if pfCpp in p.options.flags:
      result = newTree(nkPar, parseLambda(p))
    else:
      raise newException(ERetryParsing, "did not expect " & $tok)
  else:
    # probably from a failed sub expression attempt, try a type cast
    raise newException(ERetryParsing, "did not expect " & $tok)

proc leftBindingPower(p: var Parser, tok: ref Token): int =
  case tok.xkind
  of pxComma:
    result = 10
    # throw == 20
  of pxAsgn, pxPlusAsgn, pxMinusAsgn, pxStarAsgn, pxSlashAsgn, pxModAsgn,
     pxShlAsgn, pxShrAsgn, pxAmpAsgn, pxHatAsgn, pxBarAsgn:
    result = 30
  of pxConditional:
    result = 40
  of pxBarBar:
    result = 50
  of pxAmpAmp:
    result = 60
  of pxBar:
    result = 70
  of pxHat:
    result = 80
  of pxAmp:
    result = 90
  of pxEquals, pxNeq:
    result = 100
  of pxLt, pxLe, pxGt, pxGe:
    result = 110
  of pxShl, pxShr:
    result = 120
  of pxPlus, pxMinus:
    result = 130
  of pxStar, pxSlash, pxMod:
    result = 140
    # .* ->* == 150
  of pxPlusPlus, pxMinusMinus, pxParLe, pxDot, pxArrow, pxArrowStar,
     pxBracketLe:
    result = 160
    # :: == 170
  else:
    result = 0

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

proc expression(p: var Parser, rbp: int = 0; parent: PNode = nil): PNode =
  var tok = p.tok[]
  getTok(p, parent)

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
    elif semicolonRequired: parError(p, "expected ';'")
  assert result != nil

proc declarationOrStatement(p: var Parser): PNode
proc semicolonedExpression(p: var Parser): PNode =
  if p.tok.xkind != pxSymbol:
    result = expression(p)
  else:
    saveContext(p)
    var parOpen = 0
    var hasSemicolon = false
    while true:
      case p.tok.xkind
      of pxEof: break
      of pxParLe: inc parOpen
      of pxParRi:
        if parOpen == 0:
          break
        dec parOpen
      of pxSemicolon:
        hasSemicolon = true
      else: discard
      getTok(p)
    backtrackContext(p)
    if hasSemicolon:
      let decl = declarationOrStatement(p)
      let a = expression(p)
      result = newTree(nkStmtListExpr, decl, a)
    else:
      result = expression(p)

proc parseIf(p: var Parser): PNode =
  # we parse additional "else if"s too here for better Nim code
  result = newNodeP(nkIfStmt, p)
  while true:
    getTok(p) # skip ``if``
    if p.tok.xkind == pxSymbol and p.tok.s == "constexpr" and pfCpp in p.options.flags:
      getTok(p)
    var branch = newNodeP(nkElifBranch, p)
    skipCom(p, branch)
    eat(p, pxParLe, branch)
    addSon(branch, semicolonedExpression(p))
    eat(p, pxParRi, branch)
    addSon(branch, nestedStatement(p))
    addSon(result, branch)
    skipCom(p, branch)
    if p.tok.xkind == pxSymbol and p.tok.s == "else":
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
  addSon(result, semicolonedExpression(p))
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
  var exp = semicolonedExpression(p)
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

proc parseTuple(p: var Parser, statements: PNode): PNode =
  parseStructBody(p, statements, nkTupleTy)

proc parseTrailingDefinedIdents(p: var Parser, result, baseTyp: PNode) =
  var varSection = newNodeP(nkVarSection, p)
  while p.tok.xkind notin {pxEof, pxSemicolon}:
    var t = pointer(p, baseTyp)
    expectIdent(p)
    var def = newNodeP(nkIdentDefs, p)
    addSon(def, varIdent(p.tok.s, p, nkVarSection))
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
      var t = parseStruct(p, result)
      if t.isNil:
        result = newNodeP(nkDiscardStmt, p)
        result.add(newStrNodeP(nkStrLit, "forward decl of " & origName, p))
        return
      var typeSection = newNodeP(nkTypeSection, p)
      addTypeDef(typeSection, structPragmas(p, name, origName, isUnion), t,
                 genericParams)
      addSon(result, typeSection)
      parseTrailingDefinedIdents(p, result, name)
    else:
      let t =
        if isUnion: parseInnerStruct(p, result, isUnion=true, "")
        else: parseTuple(p, result)
      parseTrailingDefinedIdents(p, result, t)
  else:
    backtrackContext(p)
    result = declaration(p)

proc varDeclOrStatement(p: var Parser): PNode =
  case p.tok.xkind
  of pxSemicolon:
    result = newNodeP(nkEmpty, p)
  of pxSymbol:
    saveContext(p)
    getTok(p) # skip identifier to look ahead

    if pfCpp in p.options.flags and p.tok.xkind == pxScope:
      # match qualified identifier eg. `std::ostream`
      backtrackContext(p)
      saveContext(p)
      let retType = typeAtom(p)
      discard pointer(p, retType)

    case p.tok.xkind
    of pxSymbol, pxStar, pxLt, pxAmp, pxAmpAmp:
      # we parse
      # a b
      # a * b
      # always as declarations! This is of course not correct, but good
      # enough for most real world C code out there.
      backtrackContext(p)
      result = declarationWithoutSemicolon(p)
    else:
      backtrackContext(p)
      result = expression(p)
  else:
    result = expression(p)

proc parseFor(p: var Parser, result: PNode) =
  # 'for' '(' expression_statement expression_statement expression? ')'
  #   statement
  getTok(p, result)
  eat(p, pxParLe, result)
  var initStmt = varDeclOrStatement(p)
  if p.tok.xkind == pxColon:
    var w = newNodeP(nkForStmt, p)
    getTok(p, w)
    # C++ 'for each' loop
    if initStmt.kind != nkEmpty:
      for i in 0..<initStmt.len:
        for j in 0..<initStmt[i].len-2:
          w.add initStmt[i][j]
    else:
      parError(p, "declaration expected")
    let iter = expression(p)
    eat(p, pxParRi, iter)
    w.add iter
    addSon(w, nestedStatement(p))
    addSon(result, w)
  else:
    if p.tok.xkind == pxSemicolon:
      getTok(p, initStmt)
    if initStmt.kind != nkEmpty:
      embedStmts(result, initStmt)
    # classical 'for' loop
    var w = newNodeP(nkWhileStmt, p)
    var condition = expressionStatement(p)
    if condition.kind == nkEmpty: condition = newIdentNodeP("true", p)
    addSon(w, condition)
    var step = if p.tok.xkind != pxParRi: expression(p) else: emptyNode
    eat(p, pxParRi, step)
    if step.kind != nkEmpty:
      p.continueActions.add step
    var loopBody = nestedStatement(p)
    if step.kind != nkEmpty:
      loopBody = buildStmtList(loopBody)
      embedStmts(loopBody, step)
    if step.kind != nkEmpty:
      discard p.continueActions.pop()
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
    # translate empty statement list to Nim's ``discard`` statement
    result = newNodeP(nkDiscardStmt, p)
    result.add(emptyNode)

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
  addSon(result, semicolonedExpression(p))
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
    of "using":
      if pfCpp in p.options.flags:
        while p.tok.xkind notin {pxEof, pxSemicolon}: getTok(p)
        eat(p, pxSemicolon)
        continue
      else:
        parError(p, "'case' expected")
    else:
      parError(p, "'case' expected")
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

proc skipToSemicolon(p: var Parser; err: string; exitForCurlyRi=true): PNode =
  result = newNodeP(nkCommentStmt, p)
  result.comment = "!!!Ignored construct: "
  var inCurly = 0
  while p.tok.xkind != pxEof:
    result.comment.add " "
    result.comment.add $p.tok[]
    case p.tok.xkind
    of pxCurlyLe: inc inCurly
    of pxCurlyRi:
      if inCurly == 0 and exitForCurlyRi:
        break
      dec inCurly
    of pxSemicolon:
      if inCurly == 0:
        getTok(p)
        break
    else: discard
    getTok(p)
  result.comment.add "\nError: " & err & "!!!"

proc compoundStatement(p: var Parser; newScope=true): PNode =
  result = newNodeP(nkStmtList, p)
  eat(p, pxCurlyLe)
  if newScope: inc(p.scopeCounter)

  if pfStrict in p.options.flags:
    while p.tok.xkind notin {pxEof, pxCurlyRi}:
      var a = statement(p)
      if a.kind == nkEmpty: break
      embedStmts(result, a)
  else:
    while p.tok.xkind notin {pxEof, pxCurlyRi}:
      saveContextB(p, true)
      try:
        var a = statement(p)
        closeContextB(p)
        if a.kind == nkEmpty: break
        embedStmts(result, a)
      except ERetryParsing:
        let m = getCurrentExceptionMsg()
        backtrackContextB(p)
        # skip to the next sync point (which is a not-nested ';')
        result.add skipToSemicolon(p, m)

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

  let nname = if not p.currentClass.isNil and p.currentClass.kind == nkIdent:
                p.currentClass.ident.s
              else:
                origName
  let oname = if isDestructor: p.options.destructor & nname
              else: p.options.constructor & nname
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
  skipThrowSpecifier(p, pragmas)
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
    elif p.tok.s == "delete":
      # Deleted constructors should just be ignored.
      eat(p, pxSymbol)
      eat(p, pxSemicolon)
      return emptyNode
    elif p.tok.xkind == pxIntLit:
      eat(p, pxIntLit)
      eat(p, pxSemicolon)
    else:
      parError(p, "expected 'default' or 'delete'")
  else:
    parError(p, "expected ';'")
  if result.sons[bodyPos].kind == nkEmpty:
    if isDestructor:
      doImportCpp("#.~" & origName & "()", pragmas, p)
    else:
      let iname = cppImportName(p, "", nil, true)
      doImportCpp(iname & "(@)", pragmas, p)
  elif isDestructor:
    addSon(pragmas, newIdentNodeP("destructor", p))
  if sonsLen(result.sons[pragmasPos]) == 0:
    result.sons[pragmasPos] = emptyNode

proc parseMethod(p: var Parser, origName: string, rettyp, pragmas: PNode,
                 isStatic, isOperator: bool;
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
  skipThrowSpecifier(p, pragmas)
  case p.tok.xkind
  of pxSemicolon: getTok(p)
  of pxCurlyLe:
    let body = compoundStatement(p)
    if pfKeepBodies in p.options.flags:
      result.sons[bodyPos] = body
  of pxAsgn:
    getTok(p)
    if p.tok.s == "delete":
      eat(p, pxSymbol)
      eat(p, pxSemiColon)
      return emptyNode
    else:
      # '= 0' aka abstract method:
      eat(p, pxIntLit)
      eat(p, pxSemicolon)
  else:
    parError(p, "expected ';'")
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
                          genericParams: PNode,
                          tmplParams: PNode = emptyNode): PNode

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

proc usingStatement(p: var Parser): PNode =
  result = newNodeP(nkTypeSection, p)
  getTok(p) # skip "using"

  var isTypeDecl = false
  saveContext(p)
  if p.tok.xkind == pxSymbol:
    getTok(p, nil) # skip identifier
    if p.tok.xkind == pxAsgn:
      isTypeDecl = true
  backtrackContext(p)

  if isTypeDecl:
    markTypeIdent(p, nil)
    let usingName = skipIdentExport(p, skType)
    eat(p, pxAsgn)
    var td = newNodeP(nkTypeDef, p)
    td.addSon(usingName, emptyNode, typeName(p))
    result.add td
  else:
    # some "using" statement we don't care about:
    while p.tok.xkind notin {pxEof, pxSemicolon}: getTok(p)
    eat(p, pxSemicolon)
    result = newNodeP(nkCommentStmt, p)
    result.comment = "using statement"

proc toVariableDecl(def: PNode; isConst: bool): PNode =
  result = newNodeI(if isConst: nkConstSection else: nkVarSection, def.info)
  result.add def

proc parseVisibility(p: var Parser; result: PNode; private: var bool) =
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
    elif p.tok.xkind == pxSemicolon:
      getTok(p, result)
    else:
      break

proc parseClassEntity(p: var Parser; genericParams: PNode; private: bool): PNode =
  result = newNodeP(nkStmtList, p)
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
  if p.tok.xkind == pxSymbol and p.tok.s == "friend":
    # we skip friend declarations:
    while p.tok.xkind notin {pxEof, pxSemicolon}: getTok(p)
    eat(p, pxSemicolon)
  elif p.tok.xkind == pxSymbol and p.tok.s == "using":
    result = usingStatement(p)
  elif p.tok.xkind == pxSymbol and p.tok.s == "enum":
    let x = enumSpecifier(p, result)
    if not private or pfKeepBodies in p.options.flags: result.add x
  elif p.tok.xkind == pxSymbol and p.tok.s == "typedef":
    let x = parseTypeDef(p)
    if not private or pfKeepBodies in p.options.flags: result = x
  elif p.tok.xkind == pxSymbol and p.tok.s in ["struct", "class"]:
    let x = parseStandaloneClass(p, isStruct=p.tok.s == "struct", gp, tmpl)
    if not private or pfKeepBodies in p.options.flags: result = x
  elif p.tok.xkind == pxSymbol and p.tok.s == "union":
    let x = parseStandaloneStruct(p, isUnion=true, gp)
    if not private or pfKeepBodies in p.options.flags: result = x
  elif p.tok.xkind == pxCurlyRi: discard
  else:
    var pragmas = newNodeP(nkPragma, p)
    parseCallConv(p, pragmas)
    var isStatic = false
    if p.tok.xkind == pxSymbol and p.tok.s == "virtual":
      getTok(p, result)
    if p.tok.xkind == pxSymbol and p.tok.s == "explicit":
      getTok(p, result)
    if p.tok.xkind == pxSymbol and p.tok.s == "static":
      getTok(p, result)
      isStatic = true
    # skip constexpr for now
    var isConst = false
    if p.tok.xkind == pxSymbol and p.tok.s in ["constexpr", "consteval", "constinit"]:
      getTok(p, result)
      isConst = true

    parseCallConv(p, pragmas)
    if p.tok.xkind == pxSymbol and p.tok.s == p.currentClassOrig and
        followedByParLe(p):
      # constructor
      let cons = parseConstructor(p, pragmas, isDestructor=false,
                                  gp, genericParams)
      if not private or pfKeepBodies in p.options.flags: result.add(cons)
    elif p.tok.xkind == pxTilde:
      # destructor
      getTok(p, result)
      if p.tok.xkind == pxSymbol and p.tok.s == p.currentClassOrig:
        let des = parseConstructor(p, pragmas, isDestructor=true,
                                    gp, genericParams)
        if not private or pfKeepBodies in p.options.flags: result.add(des)
      else:
        parError(p, "invalid destructor")
    elif p.tok.xkind == pxSymbol and p.tok.s == "operator":
      let origName = getConverterCppType(p)
      var baseTyp = typeAtom(p)
      var t = pointer(p, baseTyp)
      let meth = parseMethod(p, origName, t, pragmas, isStatic, true,
                              gp, genericParams)
      if not private or pfKeepBodies in p.options.flags:
        meth.kind = nkConverterDef
        # don't add trivial operators that Nim ends up using anyway:
        if origName notin ["=", "!=", ">", ">="]:
          result.add(meth)
    else:
      # field declaration or method:
      if p.tok.xkind == pxSemicolon:
        getTok(p)
        skipCom(p, result)
      var baseTyp = typeAtom(p)
      while true:
        var def = newNodeP(nkIdentDefs, p)
        var t = pointer(p, baseTyp)
        var origName: string
        if p.tok.xkind == pxSymbol:
          if p.tok.s == "operator":
            origName = ""
            var isConverter = parseOperator(p, origName)
            let meth = parseMethod(p, origName, t, pragmas, isStatic, true,
                                   gp, genericParams)
            if not private or pfKeepBodies in p.options.flags:
              if isConverter: meth.kind = nkConverterDef
              # don't add trivial operators that Nim ends up using anyway:
              if origName notin ["=", "!=", ">", ">="]:
                result.add(meth)
            break
          origName = p.tok.s

        var fieldPointers = 0
        var i = parseField(p, nkRecList, fieldPointers)
        if origName.len > 0 and p.tok.xkind == pxParLe:
          let meth = parseMethod(p, origName, t, pragmas, isStatic, false,
                                 gp, genericParams)
          if not private or pfKeepBodies in p.options.flags:
            result.add(meth)
        else:
          t = pointersOf(p, parseTypeSuffix(p, t), fieldPointers)
          i = parseBitfield(p, i)
          var value = emptyNode
          if p.tok.xkind == pxAsgn:
            getTok(p, def)
            value = assignmentExpression(p)
          elif p.tok.xkind == pxCurlyLe:
            value = parseInitializer(p, nkTupleConstr, discardVarParam(bool))
          if not private or pfKeepBodies in p.options.flags:
            addSon(def, i, t, value)
          if not isStatic:
            addSon(result, def)
          elif pfKeepBodies in p.options.flags:
            addSon(result, toVariableDecl(def, isConst))
        if p.tok.xkind != pxComma: break
        getTok(p, def)
      if p.tok.xkind == pxSemicolon:
        if result.len > 0:
          getTok(p, lastSon(result))
        else:
          getTok(p, result)

proc parseClassEntityPp(p: var Parser; genericParams: PNode;
                       private: bool): PNode =
  # like `parseClassEntity` but with preprocessor support.
  proc parseClassEntityWrapper(p: var Parser): PNode {.nimcall.} =
    assert p.currentSection != nil
    result = parseClassEntity(p, p.currentSection.genericParams,
      p.currentSection.private)

  if p.tok.xkind == pxDirective or p.tok.xkind == pxDirectiveParLe:
    let oldCurrentSection = p.currentSection
    p.currentSection = Section(genericParams: genericParams, private: private)
    result = parseDir(p, parseClassEntityWrapper)
    p.currentSection = oldCurrentSection
  else:
    result = parseClassEntity(p, genericParams, private)

proc unpackClassSnippet(p: var Parser; snippet, recList, stmtList, condition: PNode) =
  case snippet.kind
  of nkStmtList:
    for ch in snippet:
      unpackClassSnippet(p, ch, recList, stmtList, condition)
  of nkWhenStmt:
    # most complex case: append fields to the recList and everything else
    # to the stmtList but duplicate the 'when' condition:
    var prevConditions = condition
    for branch in snippet:
      var thisCondition = prevConditions
      if branch.kind == nkElifBranch:
        if thisCondition == nil:
          thisCondition = branch[0]
        else:
          thisCondition = newTree(nkInfix, newIdentNodeP("and", p), prevConditions, thisCondition)
      unpackClassSnippet(p, lastSon(branch), recList, stmtList, thisCondition)
      if branch.kind == nkElifBranch:
        let notExpr = newTree(nkPrefix, newIdentNodeP("not", p), branch[0])
        if prevConditions == nil:
          prevConditions = notExpr
        else:
          prevConditions = newTree(nkInfix, newIdentNodeP("and", p), prevConditions, notExpr)
  of nkRecList:
    if condition != nil:
      recList.add newTree(nkWhenStmt, newTree(nkElifBranch, condition, snippet))
    else:
      for ch in snippet:
        recList.add ch
  of nkIdentDefs:
    if condition != nil:
      recList.add newTree(nkWhenStmt, newTree(nkElifBranch, condition, snippet))
    else:
      recList.add snippet
  else:
    if condition != nil:
      stmtList.add newTree(nkWhenStmt, newTree(nkElifBranch, condition, snippet))
    else:
      stmtList.add snippet

proc parseClassSnippet(p: var Parser; recList, stmtList: PNode; genericParams: PNode; private: bool) =
  # recList and stmtList are appended to.
  let entity = parseClassEntityPp(p, genericParams, private)
  unpackClassSnippet(p, entity, recList, stmtList, nil)

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

  if pfStrict in p.options.flags:
    while p.tok.xkind notin {pxEof, pxCurlyRi}:
      skipCom(p, stmtList)
      parseVisibility(p, result, private)
      parseClassSnippet(p, recList, stmtList, genericParams, private)
      opt(p, pxSemicolon, nil)
  else:
    while p.tok.xkind notin {pxEof, pxCurlyRi}:
      saveContextB(p, true)
      try:
        skipCom(p, stmtList)
        parseVisibility(p, result, private)
        parseClassSnippet(p, recList, stmtList, genericParams, private)
        opt(p, pxSemicolon, nil)
        closeContextB(p)
      except ERetryParsing:
        let err = getCurrentExceptionMsg()
        backtrackContextB(p)
        # skip to the next sync point (which is a not-nested ';')
        stmtList.add skipToSemicolon(p, err)

  eat(p, pxCurlyRi, result)

proc parseStandaloneClass(p: var Parser, isStruct: bool;
                          genericParams: PNode,
                          tmplParams: PNode = emptyNode): PNode =
  result = newNodeP(nkStmtList, p)
  saveContext(p)
  getTok(p, result) # skip "class" or "struct"
  let oldClass = p.currentClass
  var oldClassOrig = p.currentClassOrig
  var oldToMangle: StringTableRef
  p.currentClassOrig = ""
  if p.tok.xkind == pxSymbol:
    markTypeIdent(p, nil)
    p.currentClassOrig = p.tok.s
    getTok(p, result)
    if not oldClass.isNil and oldClass.kind == nkIdent:
      p.currentClass = mangledIdent(oldClass.ident.s &
                                    p.currentClassOrig, p, skType)
      p.options.toMangle[p.currentClassOrig] = p.currentClass.ident.s
    else:
      p.currentClass = mangledIdent(p.currentClassOrig, p, skType)
    deepCopy(oldToMangle, p.options.toMangle)
    p.classHierarchy.add(p.currentClassOrig)
    p.classHierarchyGP.add(tmplParams)
  else:
    p.currentClass = nil
    p.classHierarchy.add("")
    p.classHierarchyGP.add(emptyNode)
  if p.tok.xkind in {pxCurlyLe, pxSemiColon, pxColon}:
    if p.currentClass != nil:
      p.options.classes[p.currentClassOrig] = p.currentClass.ident.s

      var typeSection = newNodeP(nkTypeSection, p)
      addSon(result, typeSection)

      var name = p.currentClass #mangledIdent(p.currentClassOrig, p, skType)
      var t = parseClass(p, isStruct, result, genericParams)
      discard p.classHierarchy.pop() # pop before calling structPragmas
      discard p.classHierarchyGP.pop()
      if t.isNil:
        result = newNodeP(nkDiscardStmt, p)
        result.add(newStrNodeP(nkStrLit, "forward decl of " & p.currentClassOrig, p))
        p.currentClass = oldClass
        p.currentClassOrig = oldClassOrig
        p.options.toMangle = oldToMangle
        return result
      addTypeDef(typeSection, structPragmas(p, name, p.currentClassOrig, false, tmplParams), t,
                 genericParams)
      parseTrailingDefinedIdents(p, result, name)
    else:
      var t = parseTuple(p, result)
      discard p.classHierarchy.pop()
      discard p.classHierarchyGP.pop()
      parseTrailingDefinedIdents(p, result, t)
  else:
    backtrackContext(p)
    result = declaration(p)
  p.currentClass = oldClass
  p.currentClassOrig = oldClassOrig
  p.options.toMangle = oldToMangle

proc unwrap(a: PNode): PNode =
  if a.kind == nkPar:
    return a.sons[0]
  return a

proc fullTemplate(p: var Parser): PNode =
  let tmpl = parseTemplate(p)
  expectIdent(p)
  case p.tok.s
  of "union": result = parseStandaloneStruct(p, isUnion=true, tmpl)
  of "struct": result = parseStandaloneClass(p, isStruct=true, tmpl, tmpl)
  of "class": result = parseStandaloneClass(p, isStruct=false, tmpl, tmpl)
  else: result = declaration(p, tmpl)

proc parseContinue(p: var Parser): PNode =
  var cont = newNodeP(nkContinueStmt, p)
  getTok(p)
  eat(p, pxSemicolon)
  addSon(cont, emptyNode)

  if p.continueActions.len > 0:
    result = newNodeP(nkStmtList, p)
    for i in countdown(high(p.continueActions), 0):
      result.add copyTree(p.continueActions[i])
    result.add cont
  else:
    result = cont

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
      result = parseContinue(p)
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
    of "enum":
      var afterStatements = newNodeP(nkStmtList, p)
      result = enumSpecifier(p, afterStatements)
      if afterStatements.len > 0:
        let a = result
        result = newNodeP(nkStmtList, p)
        result.add a
        for x in afterStatements: result.add x
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
        var oldNamespace = p.currentNamespace
        if p.tok.xkind == pxSymbol:
          p.currentNamespace &= p.tok.s & "::"
          getTok(p)
        if p.tok.xkind != pxCurlyLe:
          parError(p, "expected " & tokKindToStr(pxCurlyLe))
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
        result = usingStatement(p)
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
      result = newNodeP(nkCommentStmt, p)
      result.comment = "ignored statement"
  else:
    result = expressionStatement(p)
  assert result != nil

proc parseStrict(p: var Parser): PNode =
  try:
    result = newNodeP(nkStmtList, p)
    getTok(p) # read first token
    while p.tok.xkind != pxEof:
      var s = statement(p)
      if s.kind != nkEmpty: embedStmts(result, s)
  except ERetryParsing:
    parError(p, getCurrentExceptionMsg())
    #"Uncaught parsing exception raised")

proc parseWithSyncPoints(p: var Parser): PNode =
  result = newNodeP(nkStmtList, p)
  getTok(p) # read first token
  var firstError = ""
  while p.tok.xkind != pxEof:
    saveContextB(p, true)
    try:
      var s = statement(p)
      if s.kind != nkEmpty:
        embedStmts(result, s)
      closeContextB(p)
    except ERetryParsing:
      let err = getCurrentExceptionMsg()
      if firstError.len == 0: firstError = err
      backtrackContextB(p)
      # skip to the next sync point (which is a not-nested ';')
      result.add skipToSemicolon(p, err, exitForCurlyRi=false)

proc parseUnit*(p: var Parser): PNode =
  if pfStrict in p.options.flags:
    result = parseStrict(p)
  else:
    result = parseWithSyncPoints(p)
