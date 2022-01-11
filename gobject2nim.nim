#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Custom logic postprocessor for "gobject" related code (GTK, GDK, etc.).
## Things it does:
## - Use inheritance based on `parent_instance` and `parent_class`.
## - Generates a high level wrapper offering strings and refs.

import std / [tables, os]

import compiler/[ast, renderer, idents, lineinfos]

import clexer

type
  Context = object
    m: PNode # the high level wrapping code
    info: TLineInfo

proc getName(n: PNode): PNode =
  result = n
  if result.kind == nkPragmaExpr:
    result = result[0]
  if result.kind == nkPostFix:
    result = result[1]

proc createWrapperForCallback(c: var Context; name, typ: PNode) =
  discard "to implement"

proc traverseObject(c: var Context; n: PNode; inheritsFrom: var PNode) =
  case n.kind
  of nkRecList, nkStmtList:
    for ch in n:
      traverseObject(c, ch, inheritsFrom)
  of nkIdentDefs:
    let typ = n[n.len-2]
    let name = getName(n[0])
    if name.kind == nkIdent and name.ident.s in ["parentInstance", "parentClass"]:
      inheritsFrom = newTree(nkOfInherit, typ)
      n.kind = nkEmpty
    elif typ.kind == nkProcTy:
      createWrapperForCallback(c, name, typ)
  else:
    discard

proc handleObjectDecl(c: var Context; n: PNode) =
  if n.kind == nkObjectTy:
    var inheritsFrom = PNode(nil)
    traverseObject(c, n[2], inheritsFrom)
    if inheritsFrom != nil:
      n[1] = inheritsFrom

proc pp(c: var Context; n: PNode) =
  case n.kind
  of nkTypeSection:
    for i in 0 ..< n.len:
      if n[i].kind == nkTypeDef:
        handleObjectDecl(c, n[i].lastSon)
  else:
    for i in 0 ..< n.safeLen: pp(c, n.sons[i])

proc postprocessGObject*(n: PNode; name: string): PNode =
  var c = Context(m: newNode(nkStmtList), info: unknownLineInfo())
  c.m.add newTree(nkImportStmt, newIdentNode(getIdent(identCache, name), c.info))
  pp(c, n)
  result = c.m

import c2nim

handleCmdLine proc (n: PNode; cfilename: string): PNode =
  result = n
  let (path, name, ext) = splitFile(cfilename)
  let highLevelWrapper = postprocessGObject(n, name)
  myRenderModule(highLevelWrapper, path / ((name & "_hll").changeFileExt(".nim")))
