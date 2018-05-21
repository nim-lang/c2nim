#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Postprocessor. For now only fixes identifiers that ended up producing a
## Nim keyword. It rewrites that to the backticks notation.

import compiler/ast, compiler/renderer, compiler/idents

proc pp(n: var PNode, stmtList: PNode = nil, idx: int = -1) =
  case n.kind
  of nkIdent:
    if renderer.isKeyword(n.ident):
      let m = newNodeI(nkAccQuoted, n.info)
      m.add n
      n = m
  of nkInfix, nkPrefix, nkPostfix:
    for i in 1 ..< n.safeLen: pp(n.sons[i], stmtList, idx)
  of nkAccQuoted: discard

  of nkStmtList:
    for i in 0 ..< n.safeLen: pp(n.sons[i], n, i)
  of nkRecList:
    var consts: seq[int] = @[]
    for i in 0 ..< n.safeLen:
      pp(n.sons[i], stmtList, idx)
      if n.sons[i].kind == nkConstSection:
        consts.insert(i)
    for i in consts:
      var c = n.sons[i]
      delete(n.sons, i)
      insert(stmtList.sons, c, idx)

  else:
    for i in 0 ..< n.safeLen: pp(n.sons[i], stmtList, idx)

proc postprocess*(n: PNode): PNode =
  result = n
  pp(result)

proc newIdentNode(s: string; n: PNode): PNode =
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
  addSon(result, ast.emptyNode)
  # no generics:
  addSon(result, ast.emptyNode)
  addSon(result, params)
  # pragmas
  addSon(result, newTree(nkPragma, newIdentNode("dllinterf", n)))
  # empty exception tracking:
  addSon(result, ast.emptyNode)
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

