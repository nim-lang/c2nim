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

import compiler/ast, compiler/renderer

proc pp(n: var PNode, stmtList: PNode = nil) =
  case n.kind
  of nkIdent:
    if renderer.isKeyword(n.ident):
      let m = newNodeI(nkAccQuoted, n.info)
      m.add n
      n = m
  of nkInfix, nkPrefix, nkPostfix:
    for i in 1.. < n.safeLen: pp(n.sons[i], stmtList)
  of nkAccQuoted: discard

  of nkStmtList:
    for i in 0.. < n.safeLen: pp(n.sons[i], n)
  of nkRecList:
    var consts: seq[int] = @[]
    for i in 0.. < n.safeLen:
      pp(n.sons[i], stmtList)
      if n.sons[i].kind == nkConstSection:
        consts.insert(i)
    for i in consts:
      var c = n.sons[i]
      delete(n.sons, i)
      insert(stmtList.sons, c)

  else:
    for i in 0.. < n.safeLen: pp(n.sons[i], stmtList)

proc postprocess*(n: PNode): PNode =
  result = n
  pp(result)
