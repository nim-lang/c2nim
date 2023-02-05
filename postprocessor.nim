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

import std / [tables, sets, strutils]

import compiler/[ast, renderer, idents]

import clexer
from cparser import ParserFlag, dumpTree

template emptyNode: untyped = newNode(nkEmpty)

proc isEmptyStmtList(n: PNode): bool =
  result = n.kind == nkStmtList and n.len == 1 and n[0].kind == nkEmpty

type
  Context = object
    typedefs: Table[string, PNode]
    deletes: Table[string, string]
    structStructMode: bool
    reorderComments: bool
    reorderTypes: bool
    mergeBlocks: bool
    mergeDuplicates: bool

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
  let commentKinds = {nkTypeSection, nkIdentDefs, nkProcDef, nkConstSection, nkVarSection}
  template moveComment(idx, off) =
    if n[idx+off].len > 0:
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

proc removeBlankSections(n: var PNode) =
  if n.kind in {nkLetSection, nkTypeSection, nkVarSection, nkImportStmt}:
    for c in n:
      if c.kind in {nkIdent}:
        return
      if not (c.kind in {nkEmpty, nkCommentStmt} or c.len() == 0):
        return
    # echo "[warning] postprocessor: removing blank section: ", $n.info
    n = newNode(nkEmpty)

proc hasIdentChildren(n: PNode): bool = 
  case n.kind
  of nkCharLit..nkUInt64Lit, nkFloatLit..nkFloat128Lit, nkStrLit..nkTripleStrLit:
    return false
  of nkSym, nkIdent:
    return true
  else:
    for c in n:
      if hasIdentChildren(c):
        return true

proc reorderTypes(n: var PNode) = 
  ## reorder C types to be at start of file
  
  # reorder type sections
  var
    firstTypeSection = -1
    postTypeSection = -1
    typeSections: seq[PNode]
  for i in 0..<n.safeLen:
    if n[i].kind == nkTypeSection:
      firstTypeSection = i; break
  var i = n.safeLen - 1
  while i > max(firstTypeSection, 0):
    if n[i].kind == nkTypeSection:
      typeSections.add(n[i])
      n.delSon(i)
    dec(i)
  postTypeSection = firstTypeSection
  for st in typeSections:
    n.sons.insert(st, firstTypeSection+1)
    postTypeSection.inc() 

  # reorder const sections
  var
    firstConstSection = -1
    postTypeConstSection = -1
    preTypeConstSection = -1
    constSections: seq[PNode]
  for j in 0..<n.safeLen:
    if n[j].kind == nkConstSection:
      firstConstSection = j; break

  if firstTypeSection == -1:
    return

  # always create new const sects... this merge them together
  let csPost = nkConstSection.newTree()
  let csPre = nkConstSection.newTree()
  n.sons.insert(csPost, postTypeSection)
  n.sons.insert(csPre, firstTypeSection)
  # adjust nodes after the inserts
  preTypeConstSection = firstTypeSection
  firstTypeSection.inc()
  postTypeSection.inc()
  postTypeConstSection = postTypeSection
  firstConstSection.inc(2)
  
  # find any normal const sections
  var j = n.safeLen - 1
  while j >= max(firstConstSection, 0):
    if n[j].kind == nkConstSection:
      constSections.add(n[j])
      n.delSon(j)
    dec(j)

  for sect in constSections:
    for st in sect:
      let litType = not st[^1].hasIdentChildren()
      # echo "ST: ", " valKind: ", litType, " childIdent: ", hasIdentChildren(st[^1])
      # dumpTree(st[^1])
      if litType:
        n[preTypeConstSection].sons.insert(st, 0)
      else:
        n[postTypeConstSection].sons.insert(st, 0)


proc mergeSimilarBlocks(n: PNode) = 
  ## merge similar types of blocks
  ## 
  let blockKinds = {nkTypeSection, nkConstSection, nkVarSection}
  template moveBlock(idx, prev) =
    for ch in n[idx]:
      n[prev].add(newNode(nkStmtList))
      n[prev].add(ch)
    delete(n.sons, idx)
  
  var i = 0
  while i < n.safeLen - 1:
    let kind = n[i].kind
    if kind in blockKinds:
      if n[i+1].kind == kind:
        moveBlock(i+1, i)
        continue
    inc i
 
var duplicateNodeCheck: HashSet[string]

proc deletesNode(c: Context, n: var PNode) = 
  ## deletes nodes which match the names found in context.deletes
  ## 
  proc hasChild(n: PNode): bool = n.len() > 0

  var i = 0
  while i < n.safeLen:
    # handle let's
    if n[i].kind in {nkIdentDefs}:
      if n[i].hasChild() and c.deletes.hasKey( split($(n[i][0]), "*")[0] ):
        # echo "DEL:Ident"
        delete(n.sons, i)
        continue

    if n[i].kind in {nkProcDef}:
      # delete proc
      if n[i].hasChild() and c.deletes.hasKey( $(n[i][0]) ):
        # echo "DEL:Proc"
        delete(n.sons, i)
        continue

      let def = $n[i]
      if c.deletes.hasKey( def ):
        # echo "DEL:Proc"
        delete(n.sons, i)
        continue

      # delete duplicates
      if c.mergeDuplicates:
        if def in duplicateNodeCheck:
          # echo "DEL:DUPE: ", def
          delete(n.sons, i)
          continue
        else:
          duplicateNodeCheck.incl(def)

    # handle postfix -- e.g. types
    if n[i].kind in {nkPostfix}:
      if c.deletes.hasKey($n[i][1]):
        # echo "DEL:PostFix"
        n = newNode(nkEmpty)
        continue

    # handle calls
    if n[i].kind in {nkCall}:
      if c.deletes.hasKey($n[i][0]):
        # echo "DEL:Call"
        n[i] = newNode(nkEmpty)
        continue
    
    # handle imports
    if n[i].kind in {nkImportStmt}:
      deletesNode(c, n[i])
    
    # handle generic identifier
    if n[i].kind in {nkIdent}:
      if c.deletes.hasKey($n[i]):
        # echo "DEL:import"
        delete(n.sons, i)
        continue
    inc i

  n.removeBlankSections()

proc pp(c: var Context; n: var PNode, stmtList: PNode = nil, idx: int = -1) =

  if c.reorderComments:
    reorderComments(n)

  if c.deletes.len() > 0:
    deletesNode(c, n)

  if c.mergeBlocks:
    mergeSimilarBlocks(n)

  
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

  deletesNode(c, n)

proc postprocess*(n: PNode; flags: set[ParserFlag], deletes: Table[string, string]): PNode =
  var c = Context(typedefs: initTable[string, PNode](),
                  deletes: deletes,
                  structStructMode: pfStructStruct in flags,
                  reorderComments: pfReorderComments in flags,
                  reorderTypes: pfReorderTypes in flags,
                  mergeBlocks: pfMergeBlocks in flags,
                  mergeDuplicates: pfMergeDuplicates in flags)
  result = n

  if c.reorderTypes:
    reorderTypes(result)
  
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

