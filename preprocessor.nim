#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Preprocessor support

const
  c2nimSymbol = "C2NIM"

proc eatNewLine(p: var Parser, n: PNode) =
  if p.tok.xkind == pxLineComment:
    skipCom(p, n)
    if p.tok.xkind == pxNewLine: getTok(p)
  elif p.tok.xkind == pxNewLine:
    eat(p, pxNewLine)

proc skipLine(p: var Parser) =
  while p.tok.xkind notin {pxEof, pxNewLine, pxLineComment}: getTok(p)
  eatNewLine(p, nil)

proc parseDefineBody(p: var Parser, tmplDef: PNode): string =
  if p.tok.xkind == pxCurlyLe or
    (p.tok.xkind == pxSymbol and (
        declKeyword(p, p.tok.s) or stmtKeyword(p.tok.s))):
    addSon(tmplDef, statement(p))
    result = "void"
  elif p.tok.xkind in {pxLineComment, pxNewLine}:
    addSon(tmplDef, buildStmtList(newNodeP(nkNilLit, p)))
    result = "void"
  else:
    addSon(tmplDef, buildStmtList(expression(p)))
    result = "untyped"

proc ppCondExpr(p: var Parser): PNode =
  # preprocessor conditional expression, do not expand macros here
  inc p.inPreprocessorExpr
  result = expression(p)
  dec p.inPreprocessorExpr

proc parseDefine(p: var Parser; hasParams: bool): PNode =
  if hasParams:
    # a macro with parameters:
    result = newNodeP(nkTemplateDef, p)
    addSon(result, skipIdentExport(p, skTemplate))
    addSon(result, emptyNode)
    eat(p, pxParLe)
    var params = newNodeP(nkFormalParams, p)
    # return type; not known yet:
    addSon(params, emptyNode)
    if p.tok.xkind != pxParRi:
      var identDefs = newNodeP(nkIdentDefs, p)
      var isVariable = false
      while p.tok.xkind != pxParRi:
        if p.tok.xkind == pxDotDotDot:
          isVariable = true
          getTok(p)
          break
        addSon(identDefs, skipIdent(p, skParam))
        skipStarCom(p, nil)
        if p.tok.xkind != pxComma: break
        getTok(p)
      addSon(identDefs, newIdentNodeP("untyped", p))
      addSon(identDefs, emptyNode)
      addSon(params, identDefs)
      if isVariable:
        var vdefs = newNodeP(nkExprColonExpr, p)
        addSon(vdefs, newIdentNodeP("xargs", p))
        var vdecl =
          newTree(nkBracketExpr, 
            newIdentNodeP("varargs", p),
            newIdentNodeP("untyped", p))
        addSon(vdefs, vdecl)
        addSon(params, vdefs)
    eat(p, pxParRi)

    addSon(result, emptyNode) # no generic parameters
    addSon(result, params)
    addSon(result, emptyNode) # no pragmas
    addSon(result, emptyNode)
    var kind = parseDefineBody(p, result)
    params.sons[0] = newIdentNodeP(kind, p)
    eatNewLine(p, result)
  else:
    # a macro without parameters:
    result = newNodeP(nkConstSection, p)
    while true:
      var c = newNodeP(nkConstDef, p)
      addSon(c, skipIdentExport(p, skConst))
      addSon(c, emptyNode)
      skipStarCom(p, c)
      if p.tok.xkind in {pxLineComment, pxNewLine, pxEof}:
        addSon(c, newIdentNodeP("true", p))
      else:
        addSon(c, expression(p))
      addSon(result, c)
      eatNewLine(p, c)
      if p.tok.xkind == pxDirective and p.tok.s == "define":
        getTok(p)
      else:
        break
  assert result != nil

proc parseDefineAsDecls(p: var Parser; hasParams: bool): PNode =
  var origName = p.tok.s
  if hasParams:
    # a macro with parameters:
    result = newNodeP(nkProcDef, p)
    var name = skipIdentExport(p, skTemplate)
    addSon(result, name)
    addSon(result, emptyNode)
    eat(p, pxParLe)
    var params = newNodeP(nkFormalParams, p)
    # return type; not known yet:
    addSon(params, emptyNode)

    var pragmas = newNodeP(nkPragma, p)

    if p.tok.xkind != pxParRi:
      while p.tok.xkind != pxParRi:
        if p.tok.xkind == pxDotDotDot: # handle varargs
          getTok(p)
          addSon(pragmas, newIdentNodeP("varargs", p))
          break
        else:
          var vdefs = newTree(nkExprColonExpr,
            skipIdent(p, skParam),
            newIdentNodeP("untyped", p))
          addSon(params, vdefs)

          skipStarCom(p, nil)
          if p.tok.xkind != pxComma:
            break
          getTok(p)

    eat(p, pxParRi)

    let iname = cppImportName(p, origName)
    addSon(pragmas,
      newIdentStrLitPair(p.options.importcLit, iname, p),
      getHeaderPair(p))

    addSon(result, emptyNode) # no generic parameters
    addSon(result, params)
    addSon(result, pragmas) 
    addSon(result, emptyNode)

    addSon(result, emptyNode)
    skipLine(p)

  else:
    # a macro without parameters:
    result = newNodeP(nkVarTy, p)

    while true:
      let vname = skipIdentExport(p, skConst)
      # skipStarCom(p, result)
      let iname = cppImportName(p, origName)
      var vpragmas = newNodeP(nkPragma, p)
      addSon(vpragmas, newIdentStrLitPair(p.options.importcLit, iname, p))
      addSon(vpragmas, getHeaderPair(p))
      let vtype = newIdentNodeP("int", p)

      addSon(result, vname)
      addSon(result, vpragmas)
      addSon(result, vtype)

      skipCom(p, result)
      skipLine(p) # eat the rest of the define, skip parsing
      if p.tok.xkind == pxDirective and p.tok.s == "define":
        getTok(p)
      else:
        break
  assert result != nil

proc dontTranslateToTemplateHeuristic(body: seq[ref Token]; closedParentheses: int): bool =
  # we list all **binary** operators here too: As these cannot start an
  # expression, we know the resulting #define cannot be a valid Nim template.
  const InvalidAsPrefixOpr = {
    pxComma, pxColon,
    pxAmpAsgn, pxAmpAmpAsgn,
    pxBar, pxBarBar, pxBarAsgn, pxBarBarAsgn,
    pxPlusAsgn, pxMinusAsgn, pxMod, pxModAsgn,
    pxSlash, pxSlashAsgn, pxStarAsgn, pxHat, pxHatAsgn,
    pxAsgn, pxEquals, pxDot, pxDotDotDot,
    pxLe, pxLt, pxGe, pxGt, pxNeq, pxShl, pxShlAsgn, pxShr, pxShrAsgn}

  result = body.len == 0 or body[0].s.startsWith("__") or
    body[0].s in ["extern", "case", "else", "default"] or
    body[0].xkind in InvalidAsPrefixOpr or (
      body.len >= 3 and closedParentheses == 1 and
      body[0].s in ["if", "for", "switch", "while"] and body[^1].xkind == pxParRi
    )

proc parseDefBody(p: var Parser, m: var Macro, params: seq[string]): bool =
  # we return whether the body looked like a typical '#def' body. This is a
  # heuristic but it works well.
  result = false
  m.body = @[]
  # A little hack: We safe the context, so that every following token will be
  # put into a newly allocated TToken object. Thus we can just save a
  # reference to the token in the macro's body.
  saveContext(p)

  var parentheses: array[pxParLe..pxCurlyLe, int]
  var closedParentheses = 0
  while p.tok.xkind notin {pxEof, pxNewLine, pxLineComment}:
    case p.tok.xkind
    of pxDirective:
      # is it a parameter reference? (or possibly #param with a toString)
      var tok = p.tok
      for i in 0..high(params):
        if params[i] == p.tok.s:
          # over-write the *persistent* token too. This means we finally support
          # #define foo(param) #param
          # too, because `parseDef` is always called before `parseDefine`.
          tok.xkind = pxToString
          new(tok)
          tok.xkind = pxMacroParamToStr
          tok.position = i
          break
      m.body.add(tok)
    of pxSymbol, pxDirectiveParLe, pxToString:
      let isSymbol = p.tok.xkind == pxSymbol
      # is it a parameter reference? (or possibly #param with a toString)
      var tok = p.tok
      for i in 0..high(params):
        if params[i] == p.tok.s:
          new(tok)
          tok.xkind = if isSymbol: pxMacroParam else: pxMacroParamToStr
          tok.position = i
          break
      m.body.add(tok)
    of pxParLe, pxBracketLe, pxCurlyLe:
      inc(parentheses[p.tok.xkind])
      m.body.add(p.tok)
    of pxParRi, pxBracketRi, pxCurlyRi:
      let kind = correspondingOpenPar(p.tok.xkind)
      if parentheses[kind] > 0:
        dec(parentheses[kind])
        if parentheses[kind] == 0 and kind == pxParLe:
          inc closedParentheses
      else:
        # unpaired ')' or ']' or '}' --> enable "cannot translate to template heuristic"
        result = true
      m.body.add(p.tok)
    of pxInvalid:
      m.body.add(p.tok)
      result = true
    else:
      m.body.add(p.tok)
    # we do not want macro expansion here:
    rawGetTok(p)
  eatNewLine(p, nil)
  closeContext(p)
  # newline token might be overwritten, but this is not
  # part of the macro body, so it is safe.
  if dontTranslateToTemplateHeuristic(m.body, closedParentheses):
    result = true

proc parseDef(p: var Parser, m: var Macro; hasParams: bool): bool =
  m.name = p.tok.s
  rawGetTok(p)
  var params: seq[string] = @[]
  # parse parameters:
  if hasParams:
    eat(p, pxParLe)
    while p.tok.xkind != pxParRi:
      if p.tok.xkind == pxDotDotDot:
        getTok(p)
        break
      expectIdent(p)
      params.add(p.tok.s)
      getTok(p)
      skipStarCom(p, nil)
      if p.tok.xkind != pxComma: break
      getTok(p)
    eat(p, pxParRi)
  m.params = if hasParams: params.len else: -1
  result = parseDefBody(p, m, params)

proc isDir(p: Parser, dir: string): bool =
  result = p.tok.xkind in {pxDirectiveParLe, pxDirective} and p.tok.s == dir

proc parseInclude(p: var Parser): PNode =
  result = newNodeP(nkImportStmt, p)
  while isDir(p, "include"):
    getTok(p) # skip "include"
    if p.tok.xkind == pxStrLit and pfSkipInclude notin p.options.flags:
      let file = mangledIdent(changeFileExt(p.tok.s, ""), p, skVar)
      #newStrNodeP(nkStrLit, changeFileExt(p.tok.s, ""), p)
      addSon(result, file)
      getTok(p)
      skipStarCom(p, file)
      eatNewLine(p, nil)
    else:
      skipLine(p)
  if sonsLen(result) == 0:
    # we only parsed includes that we chose to ignore:
    result = emptyNode

proc definedExprAux(p: var Parser): PNode =
  result = newNodeP(nkCall, p)
  addSon(result, newIdentNodeP("defined", p))
  addSon(result, skipIdent(p, skDontMangle))

proc parseStmtList(p: var Parser; sectionParser: SectionParser): PNode =
  result = newNodeP(nkStmtList, p)
  while true:
    case p.tok.xkind
    of pxEof: break
    of pxDirectiveParLe, pxDirective:
      case p.tok.s
      of "else", "endif", "elif": break
      else: discard
    else: discard
    addSon(result, sectionParser(p))

proc eatEndif(p: var Parser) =
  if isDir(p, "endif"):
    skipLine(p)
  else:
    parMessage(p, errXExpected, "#endif")

proc parseIfDirAux(p: var Parser, result: PNode; sectionParser: SectionParser) =
  addSon(result.sons[0], parseStmtList(p, sectionParser))
  while isDir(p, "elif"):
    var b = newNodeP(nkElifBranch, p)
    getTok(p)
    addSon(b, ppCondExpr(p))
    eatNewLine(p, nil)
    addSon(b, parseStmtList(p, sectionParser))
    addSon(result, b)
  if isDir(p, "else"):
    var s = newNodeP(nkElse, p)
    skipLine(p)
    addSon(s, parseStmtList(p, sectionParser))
    addSon(result, s)
  eatEndif(p)

proc skipUntilEndif(p: var Parser) =
  var nested = 1
  while p.tok.xkind != pxEof:
    if isDir(p, "ifdef") or isDir(p, "ifndef") or isDir(p, "if"):
      inc(nested)
    elif isDir(p, "endif"):
      dec(nested)
      if nested <= 0:
        skipLine(p)
        return
    getTok(p)
  parMessage(p, errXExpected, "#endif")

type
  TEndifMarker = enum
    emElif, emElse, emEndif

proc skipUntilElifElseEndif(p: var Parser): TEndifMarker =
  var nested = 1
  while p.tok.xkind != pxEof:
    if isDir(p, "ifdef") or isDir(p, "ifndef") or isDir(p, "if"):
      inc(nested)
    elif isDir(p, "elif") and nested <= 1:
      return emElif
    elif isDir(p, "else") and nested <= 1:
      return emElse
    elif isDir(p, "endif"):
      dec(nested)
      if nested <= 0:
        return emEndif
    getTok(p)
  parMessage(p, errXExpected, "#endif")

# Returns `true` if there is a declaration
#   #assumedef `s`
# or there is a macro with name `s`.
proc defines(p: Parser, s: string): bool =
  if p.options.assumeDef.contains(s): return true
  for m in p.options.macros:
    if m.name == s:
      return true
  return false

proc isIdent(n: PNode, id: string): bool =
  n.kind == nkIdent and n.ident.s == id

proc definedGuard(n: PNode): string =
  if n.len == 2:
    let call = n.sons[0]
    if call.isIdent("defined"):
      result = n.sons[1].ident.s

proc simplify(p: Parser, n: PNode): PNode =
  # Simplifies a condition based on the following assumptions:
  # - if there is a declaration
  #   #assumedef IDENT
  # we can substitute `defined(IDENT)` with `true`
  # - if there is a declaration
  #   #assumendef IDENT
  # we can substitute `defined(IDENT)` with `false`
  # Then, boolean conditions are simplified recursively as far as possible
  let
    trueNode = newIdentNodeP("true", p)
    falseNode = newIdentNodeP("false", p)

  case n.kind
  of nkCall:
    let guard = definedGuard(n)
    if p.options.assumenDef.contains(guard):
      return falseNode
    if p.defines(guard):
      return trueNode
  of nkInfix:
    let op = n.sons[0]
    if op.isIdent("and"):
      # subconditions can be true, false or unknown
      var allTrue = true
      for i in 1 ..< n.len:
        let n1 = p.simplify(n.sons[i])
        if n1.isIdent("true"):
          discard
        elif n1.isIdent("false"):
          return falseNode
        else:
          allTrue = false
      if allTrue:
        return trueNode
    elif op.isIdent("or"):
      # subconditions can be true, false or unknown
      var allFalse = true
      for i in 1 ..< n.len:
        let n1 = p.simplify(n.sons[i])
        if n1.isIdent("true"):
          return trueNode
        elif n1.isIdent("false"):
          discard
        else:
          allFalse = false
      if allFalse:
        return falseNode
  of nkPrefix:
    if n.len == 2:
      let
        op = n.sons[0]
        n1 = p.simplify(n.sons[1])
      if op.isIdent("not"):
        if n1.isIdent("true"):
          return falseNode
        if n1.isIdent("false"):
          return trueNode
  else:
    discard
  return n

proc simplifyWhenStmt(p: Parser, n: PNode): PNode =
  assert n.kind == nkWhenStmt
  assert n.len > 0
  assert n[0].kind == nkElifBranch
  assert n[0].len == 2

  let simplified = p.simplify(n[0][0])
  if simplified.isIdent("true"):
    result = n[0][1]
  else:
    result = n

proc parseIfdef(p: var Parser; sectionParser: SectionParser): PNode =
  rawGetTok(p) # skip #ifdef
  expectIdent(p)
  if p.options.assumenDef.contains(p.tok.s):
    skipUntilEndif(p)
    result = emptyNode
  elif p.tok.s == c2nimSymbol:
    skipLine(p)
    result = parseStmtList(p, sectionParser)
    skipUntilEndif(p)
  else:
    result = newNodeP(nkWhenStmt, p)
    addSon(result, newNodeP(nkElifBranch, p))
    addSon(result.sons[0], definedExprAux(p))
    eatNewLine(p, nil)
    parseIfDirAux(p, result, sectionParser)
    result = simplifyWhenStmt(p, result)

proc isIncludeGuard(p: var Parser): bool =
  var guard = p.tok.s
  skipLine(p)
  if p.tok.xkind == pxDirective and p.tok.s == "define":
    getTok(p) # skip #define
    expectIdent(p)
    if p.tok.s == guard:
      getTok(p)
      if p.tok.xkind in {pxLineComment, pxNewLine, pxEof}:
        result = true
        skipLine(p)

proc parseIfndef(p: var Parser; sectionParser: SectionParser): PNode =
  result = emptyNode
  rawGetTok(p) # skip #ifndef
  expectIdent(p)
  if p.defines(p.tok.s):
    skipUntilEndif(p)
    result = emptyNode
  elif p.tok.s == c2nimSymbol:
    skipLine(p)
    case skipUntilElifElseEndif(p)
    of emElif:
      result = newNodeP(nkWhenStmt, p)
      addSon(result, newNodeP(nkElifBranch, p))
      getTok(p)
      addSon(result.sons[0], ppCondExpr(p))
      eatNewLine(p, nil)
      parseIfDirAux(p, result, sectionParser)
    of emElse:
      skipLine(p)
      result = parseStmtList(p, sectionParser)
      eatEndif(p)
    of emEndif: skipLine(p)
  else:
    # test if include guard:
    saveContext(p)
    if isIncludeGuard(p):
      closeContext(p)
      result = parseStmtList(p, sectionParser)
      eatEndif(p)
    else:
      backtrackContext(p)
      result = newNodeP(nkWhenStmt, p)
      addSon(result, newNodeP(nkElifBranch, p))
      var e = newNodeP(nkPrefix, p)
      addSon(e, newIdentNodeP("not", p))
      addSon(e, definedExprAux(p))
      eatNewLine(p, nil)
      addSon(result.sons[0], e)
      parseIfDirAux(p, result, sectionParser)
      result = simplifyWhenStmt(p, result)

proc parseIfDir(p: var Parser; sectionParser: SectionParser): PNode =
  result = newNodeP(nkWhenStmt, p)
  addSon(result, newNodeP(nkElifBranch, p))
  getTok(p)
  let condition = ppCondExpr(p)
  let simplified = p.simplify(condition)
  if simplified.isIdent("false"):
    skipUntilEndif(p)
    result = emptyNode
  else:
    addSon(result.sons[0], condition)
    eatNewLine(p, nil)
    parseIfDirAux(p, result, sectionParser)
    if pfAssumeIfIsTrue in p.options.flags or simplified.isIdent("true"):
      result = result.sons[0].sons[1]

proc parsePegLit(p: var Parser): Peg =
  var col = getColumn(p.lex) + 2
  getTok(p)
  if p.tok.xkind != pxStrLit: expectIdent(p)
  try:
    result = parsePeg(
      pattern = if p.tok.xkind == pxStrLit: p.tok.s else: escapePeg(p.tok.s),
      filename = toFilename(p.lex.fileIdx),
      line = p.lex.linenumber,
      col = col)
    getTok(p)
  except EInvalidPeg:
    parMessage(p, errUser, getCurrentExceptionMsg())

proc parseMangleDir(p: var Parser) =
  var pattern = parsePegLit(p)
  if p.tok.xkind != pxStrLit: expectIdent(p)
  p.options.mangleRules.add((pattern, p.tok.s))
  getTok(p)
  eatNewLine(p, nil)

proc parseOverride(p: var Parser; tab: StringTableRef) =
  getTok(p)
  expectIdent(p)
  tab[p.tok.s] = "true"
  getTok(p)
  eatNewLine(p, nil)

proc parseDir(p: var Parser; sectionParser: SectionParser): PNode =
  result = emptyNode
  assert(p.tok.xkind in {pxDirective, pxDirectiveParLe})
  case p.tok.s
  of "define":
    let hasParams = p.tok.xkind == pxDirectiveParLe
    getTok(p)
    expectIdent(p)
    let isDefOverride = p.options.toPreprocess.hasKey(p.tok.s)
    saveContext(p)

    let L = p.options.macros.len
    setLen(p.options.macros, L+1)
    if not parseDef(p, p.options.macros[L], hasParams) and not isDefOverride:
      setLen(p.options.macros, L)
      backtrackContext(p)
      if p.options.importdefines:
        result = parseDefineAsDecls(p, hasParams)
      elif p.options.importfuncdefines and hasParams:
        result = parseDefineAsDecls(p, hasParams)
      else:
        result = parseDefine(p, hasParams)
    else:
      closeContext(p)

  of "include": result = parseInclude(p)
  of "ifdef": result = parseIfdef(p, sectionParser)
  of "ifndef": result = parseIfndef(p, sectionParser)
  of "if": result = parseIfDir(p, sectionParser)
  of "cdecl", "stdcall", "ref", "skipinclude", "typeprefixes", "skipcomments",
     "keepbodies", "cpp", "nep1", "assumeifistrue", "structstruct":
    discard setOption(p.options, p.tok.s)
    getTok(p)
    eatNewLine(p, nil)
  of "header":
    var key = p.tok.s
    getTok(p)
    if p.tok.xkind == pxNewLine:
      discard setOption(p.options, key)
    else:
      if p.tok.xkind == pxStrLit:
        # try to be backwards compatible with older versions of c2nim:
        discard setOption(p.options, key, strutils.escape(p.tok.s))
      else:
        expectIdent(p)
        discard setOption(p.options, key, p.tok.s)
      getTok(p)
    eatNewLine(p, nil)
    result = emptyNode
  of "dynlib", "prefix", "suffix", "class", "discardableprefix", "assumedef", "assumendef", "isarray":
    var key = p.tok.s
    getTok(p)
    if p.tok.xkind != pxStrLit: expectIdent(p)
    discard setOption(p.options, key, p.tok.s)
    getTok(p)
    eatNewLine(p, nil)
    result = emptyNode
  of "mangle":
    parseMangleDir(p)
  of "pp":
    parseOverride(p, p.options.toPreprocess)
  of "inheritable", "pure":
    parseOverride(p, p.options.inheritable)
  of "def":
    let hasParams = p.tok.xkind == pxDirectiveParLe
    rawGetTok(p)
    expectIdent(p)
    let L = p.options.macros.len
    setLen(p.options.macros, L+1)
    discard parseDef(p, p.options.macros[L], hasParams)
  of "private":
    var pattern = parsePegLit(p)
    p.options.privateRules.add(pattern)
    eatNewLine(p, nil)
  else:
    # ignore unimportant/unknown directive ("undef", "pragma", "error")
    skipLine(p)

