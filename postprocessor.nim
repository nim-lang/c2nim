#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Postprocessor. Things it does:
## - Fixes identifiers that ended up producing a Nim keyword.
##   It rewrites that to the backticks notation.
## - Fixes some empty statement sections.
## - Tries to rewrite braced initializers to be more accurate.

import std / tables

import compiler/[ast, renderer, idents]

import clexer

template emptyNode: untyped = newNode(nkEmpty)

proc isEmptyStmtList(n: PNode): bool =
  result = n.kind == nkStmtList and n.len == 1 and n[0].kind == nkEmpty

type
  Context = object
    typedefs: Table[string, PNode]
    structStructMode: bool
    reorderComments: bool

proc getName(n: PNode): PNode =
  result = n
  if result.kind == nkPragmaExpr:
    result = result[0]
  if result.kind == nkPostFix:
    result = result[1]

proc skipColon(n: PNode): PNode =
  if n.kind == nkExprColonExpr: result = n[1]
  else: result = n

proc count(n: PNode): int =
  result = safeLen(n)
  for i in 0..<safeLen(n):
    inc result, count(n[i])

proc rememberTypedef(c: var Context; n: PNode) =
  let name = getName(n[0])
  if name.kind == nkIdent and n.len >= 2:
    if not c.structStructMode:
      c.typedefs[name.ident.s] = n
    else:
      let oldDef = c.typedefs.getOrDefault(name.ident.s)
      if oldDef == nil:
        c.typedefs[name.ident.s] = n
      else:
        # check which declaration is the better one:
        if count(n.lastSon) > count(oldDef.lastSon):
          oldDef.kind = nkEmpty # remove it
          c.typedefs[name.ident.s] = n
        else:
          n.kind = nkEmpty # remove this one

proc ithFieldName(t: PNode; position: var int): PNode =
  result = nil
  case t.kind
  of nkObjectTy:
    result = ithFieldName(t.lastSon, position)
  of nkRecList:
    for j in 0..<t.len:
      result = ithFieldName(t[j], position)
      if result != nil: return result
  of nkIdentDefs:
    for j in 0..<t.len-2:
      if position == 0:
        return getName(t[j])
      dec position
  else:
    discard

const
  Initializers = {nkBracket, nkTupleConstr}

proc patchBracket(c: Context; t: PNode; n: var PNode) =
  if n.kind notin Initializers: return
  let obj = t
  var t = t
  var attempts = 10
  while t.kind == nkIdent and attempts >= 0:
    let t2 = c.typedefs.getOrDefault(t.ident.s)
    if t2 != nil:
      t = t2.lastSon
    else:
      break
    dec attempts

  if t.kind == nkBracketExpr and t.len == 3 and t[0].kind == nkIdent and t[0].ident.s == "array":
    for i in 0..<n.len:
      patchBracket(c, t[2], n.sons[i])
    if n.kind == nkTupleConstr: n.kind = nkBracket

  elif t.kind == nkObjectTy and obj.kind == nkIdent:
    var nn = newTree(nkObjConstr, obj)
    var success = true
    for i in 0..<n.len:
      var ii = i
      let name = ithFieldName(t, ii)
      if name == nil:
        success = true
      else:
        nn.add newTree(nkExprColonExpr, name, n[i].skipColon)
    if success:
      n = nn


import sequtils

var depth = 0

proc reorderComments(n: PNode) = 
  ## reorder C style comments to Nim style ones
  var j = 1
  let commentKinds = {nkTypeSection, nkIdentDefs, nkProcDef, nkConstSection}
  template moveComment(idx, off) =
    if n[idx+off].len >= 0:
      n[idx+off][0].comment = n[idx].comment
      delete(n.sons, idx)

  while j < n.safeLen - 1:
    if n[j].kind == nkCommentStmt:
      # join comments to previous node if line numbers match
      if n[j-1].kind in commentKinds:
        if n[j-1].info.line == n[j].info.line:
          moveComment(j, -1)
    inc j
  var i = 0
  while i < n.safeLen - 1:
    if n[i].kind == nkCommentStmt:
      # reorder comments to match Nim ordering
      if n[i+1].kind in commentKinds:
        moveComment(i, +1)
    inc i

proc pp(c: var Context; n: var PNode, stmtList: PNode = nil, idx: int = -1) =

  if c.reorderComments:
    reorderComments(n)

  # var s = ""
  # inc depth
  # for i in 0..depth: s &= "  "
  # echo s, "PP: ", n.kind, " idx: ", idx, " ln: ", n.info.line, " comment: `", n.comment[0..<n.comment.len().min(45)], "`"

  case n.kind
  of nkIdent:
    if renderer.isKeyword(n.ident):
      let m = newNodeI(nkAccQuoted, n.info)
      m.add n
      n = m
  of nkInfix, nkPrefix, nkPostfix:
    for i in 1 ..< n.safeLen: pp(c, n.sons[i], stmtList, idx)
  of nkAccQuoted: discard

  of nkStmtList:
    for i in 0 ..< n.safeLen:
      pp(c, n.sons[i], n, i)

  of nkRecList:
    var consts: seq[int] = @[]
    for i in 0 ..< n.safeLen:
      pp(c, n.sons[i], stmtList, idx)
      if n.sons[i].kind == nkConstSection:
        consts.insert(i)
    for i in consts:
      var cst = n.sons[i]
      delete(n.sons, i)
      insert(stmtList.sons, cst, idx)

  of nkElifBranch:
    if n[1].len == 0 or isEmptyStmtList(n[1]):
      n[1] = newTree(nkStmtList, newTree(nkDiscardStmt, emptyNode))
    pp(c, n[0], stmtList, idx)
    pp(c, n[1], stmtList, idx)
  of nkElse:
    if n[0].len == 0 or isEmptyStmtList(n[0]):
      n[0] = newTree(nkStmtList, newTree(nkDiscardStmt, emptyNode))
    pp(c, n[0], stmtList, idx)
  of nkIdentDefs:
    let L = n.len
    for i in 0 ..< L: pp(c, n.sons[i], stmtList, idx)
    if L > 2 and n[L-2].kind != nkEmpty and n[L-1].kind in Initializers:
      patchBracket(c, n[L-2], n[L-1])

  of nkTypeSection:
    for i in 0 ..< n.len:
      if n[i].kind == nkTypeDef:
        rememberTypedef(c, n[i])
      pp(c, n.sons[i], stmtList, idx)

  else:
    for i in 0 ..< n.safeLen: pp(c, n.sons[i], stmtList, idx)

  dec depth

proc postprocess*(n: PNode; structStructMode, reorderComments: bool): PNode =
  var c = Context(typedefs: initTable[string, PNode](),
                  reorderComments: reorderComments,
                  structStructMode: structStructMode)
  result = n
  pp(c, result)

proc newIdentNode(s: string; n: PNode): PNode =
  when declared(identCache):
    result = ast.newIdentNode(getIdent(identCache, s), n.info)
  else:
    result = ast.newIdentNode(getIdent(s), n.info)

proc createDllProc(n: PNode; prefix: string): PNode =
  const oprMappings = {"&": "Band", "&&": "Land", "&=": "Bandeq",
    "&&=": "Landeq", "|": "Bor", "||": "Lor", "|=": "Boreq",
    "||=": "Loreq", "!": "Not", "++": "Plusplus", "--": "Minusminus",
    "+": "Plus", "+=": "Pluseq", "-": "Minus", "-=": "Minuseq",
    "%": "Percent", "%=": "Percenteq", "/": "Slash", "/=": "Slasheq",
    "*": "Star", "*=": "Stareq", "^": "Roof", "^=": "Roofeq",
    "=": "Asgn", "==": "Eq", ".": "Dot", "...", "Dotdotdot",
    "<=": "Le", "<": "Lt", ">=": "Ge", ">": "Gt", "!=": "Noteq",
    "?": "Quest", "<<": "Shl", "<<=": "Shleq", ">>": "Shr", ">>=": "Shreq",
    "~": "Tilde", "~=": "Tildeeq", "->": "Arrow", "->*": "Arrowstar",
    "[]": "Get", "[]=": "Set", "()": "Opcall"}

  result = newNodeI(nkProcDef, n.info)
  var name = n[namePos]
  let op = if name.kind == nkPostFix: name.lastSon else: name
  while name.kind in {nkPostFix, nkAccQuoted}:
    name = name.lastSon
  doAssert name.kind == nkIdent
  let id = name.ident.s
  var dest = prefix
  block specialop:
    for key, val in items(oprMappings):
      if id == key:
        dest.add val
        break specialop
    dest.add id
  # copy parameter list over:
  let params = copyTree(n[paramsPos])
  var call = newTree(nkCall, op)
  call.info = n.info
  for i in 1..<params.len:
    let p = params[i]
    if p.kind == nkIdentDefs:
      var typ = p[p.len-2]
      while typ.kind in {nkPtrTy, nkVarTy, nkRefTy}:
        typ = lastSon(typ)
      dest.add("_")
      dest.add renderTree(typ)
      for j in 0..p.len-3:
        call.add p[j]

  addSon(result, newTree(nkPostFix, newIdentNode("*", n),
                    newIdentNode(dest, n)))
  # no pattern:
  addSon(result, emptyNode)
  # no generics:
  addSon(result, emptyNode)
  addSon(result, params)
  # pragmas
  addSon(result, newTree(nkPragma, newIdentNode("dllinterf", n)))
  # empty exception tracking:
  addSon(result, emptyNode)
  # body:
  addSon(result, newTree(nkStmtList, call))

proc exportAsDll(n, dest: PNode; prefix: string) =
  case n.kind
  of nkStmtList, nkStmtListExpr:
    for i in 0 ..< n.len:
      exportAsDll(n[i], dest, prefix)
  of nkProcDef:
    if n.sons[genericParamsPos].kind == nkEmpty:
      dest.add createDllProc(n, prefix)
  else: discard

proc exportAsDll*(n: PNode; prefix: string): PNode =
  result = newNodeI(nkStmtList, n.info)
  exportAsDll(n, result, prefix)

