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
## - Uses inheritance based on `parent_instance` and `parent_class`.
## - Generates a high level wrapper offering strings and refs.

import std / [tables, os, strutils]

import compiler/[ast, renderer, idents, lineinfos]

import clexer

type
  Context = object
    m: PNode # the high level wrapping code
    info: TLineInfo
    refTypes: seq[string]

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

proc ident(c: var Context; s: string): PNode =
  newIdentNode(getIdent(identCache, s), c.info)

proc hasHighLevelType(s: string): bool =
  result = (s.startsWith("Gtk") or s.len > 2 and s[0] == 'G' and s[1] in {'A'..'Z'}) and
      not s.endsWith("Class")

proc toHighLevelType(s: string): string =
  if s.startsWith("Gtk"):
    s.substr(3)
  else:
    "Glib" & s.substr(1) # GApplication -> GlibApplication

proc createRefWrapper(c: var Context; n, inh: PNode) =
  let name = getName(n[0])
  if name.kind == nkIdent and hasHighLevelType(name.ident.s):
    let hname = name.ident.s.toHighLevelType
    c.refTypes.add hname
    let inheritFrom =
      if inh.kind == nkIdent and hasHighLevelType(inh.ident.s):
        newTree(nkOfInherit, c.ident(inh.ident.s.toHighLevelType))
      else:
        newNode(nkEmpty)

    c.m.add newTree(nkTypeSection,
      newTree(nkTypeDef,
        newTree(nkPostFix, c.ident"*", c.ident(hname)),
        newNode(nkEmpty), # generic params
        newTree(nkRefTy,
          newTree(nkObjectTy, newNode(nkEmpty), inheritFrom, newTree(nkRecList,
            newTree(nkIdentDefs, newTree(nkPostFix, c.ident"*", c.ident("impl")),
              newTree(nkPtrTy, name), newNode(nkEmpty))))
         )))
    c.m.add newTree(nkCall, c.ident"implementHooks", c.ident(hname))

proc handleObjectDecl(c: var Context; typedef, n: PNode) =
  if n.kind == nkObjectTy:
    var inheritsFrom = PNode(nil)
    traverseObject(c, n[2], inheritsFrom)
    if inheritsFrom != nil:
      n[1] = inheritsFrom
      createRefWrapper(c, typedef, inheritsFrom[0])

type
  WrappedProc = object
    name: string
    params: PNode
    call: PNode
    wrapInObject: PNode
    useful: bool

proc transformReturnType(c: var Context; w: var WrappedProc; n: PNode): PNode =
  if n.kind == nkPtrTy and n[0].kind == nkIdent and hasHighLevelType(n[0].ident.s):
    let ht = toHighLevelType(n[0].ident.s)
    block constructor:
      for h in mitems(c.refTypes):
        if w.name.startsWith(h.toLowerAscii() & "New"):
          w.name = "new" & h
          result = c.ident(h)
          # XXX What if it's GObject and not GtkObject?
          w.wrapInObject = newTree(nkObjConstr, result, newTree(nkExprColonExpr, c.ident"impl", newTree(nkCast, c.ident("ptr Gtk" & h), w.call)))
          break constructor
      result = c.ident ht
      w.wrapInObject = newTree(nkObjConstr, result, newTree(nkExprColonExpr, c.ident"impl", w.call))
  elif n.kind == nkIdent:
    case n.ident.s
    of "Gboolean":
      result = c.ident"bool"
      w.wrapInObject = newTree(nkInfix, c.ident"!=", w.call, newStrNode(nkIntLit, "0"))
    of "cstring":
      result = c.ident"string"
      w.wrapInObject = newTree(nkPrefix, c.ident"$", w.call)
    of "guint", "cint":
      result = c.ident"int"
      w.wrapInObject = newTree(nkCall, result, w.call)
    else:
      result = n
  else:
    result = n

proc transformParams(c: var Context; w: var WrappedProc; n: PNode) =
  w.params.add transformReturnType(c, w, n[0])
  for i in 1..<n.len:
    let it = n[i]
    if it.kind == nkIdentDefs:
      let paramName = it[0]
      let mine = copyTree(it)
      let t = it[it.len-2]
      if t.kind == nkIdent:
        case t.ident.s
        of "Gboolean":
          w.call.add newTree(nkInfix, c.ident"!=", paramName, newStrNode(nkIntLit, "0"))
          mine[mine.len-2] = c.ident"bool"
          w.useful = true
        of "cstring":
          w.call.add newTree(nkCall, c.ident"cstring", paramName)
          mine[mine.len-2] = c.ident"string"
          w.useful = true
        of "guint":
          w.call.add newTree(nkCall, c.ident"guint", paramName)
          mine[mine.len-2] = c.ident"int"
          w.useful = true
        of "cint":
          w.call.add newTree(nkCall, c.ident"cint", paramName)
          mine[mine.len-2] = c.ident"int"
          w.useful = true
        of "cstringArray":
          # TODO
          w.call.add paramName
        else:
          w.call.add paramName
      elif t.kind == nkPtrTy and t[0].kind == nkIdent and hasHighLevelType(t[0].ident.s):
        let hname = t[0].ident.s.substr(3)
        mine[mine.len-2] = c.ident(hname)
        w.call.add newTree(nkDotExpr, paramName, c.ident"impl")
        w.useful = true
      else:
        w.call.add paramName
      w.params.add mine

proc handleProc(c: var Context; n: PNode) =
  let name = getName(n[0])
  if name.kind != nkIdent: return

  var result = newNodeI(nkProcDef, c.info)
  var w = WrappedProc(name: name.ident.s,
                      params: newNode(nkFormalParams),
                      call: newTree(nkCall, name),
                      wrapInObject: nil)

  transformParams(c, w, n[paramsPos])
  addSon(result, newTree(nkPostFix, c.ident"*", c.ident(w.name)))
  # no pattern:
  addSon(result, newNode(nkEmpty))
  # no generics:
  addSon(result, newNode(nkEmpty))
  addSon(result, w.params)
  addSon(result, newNode(nkEmpty))
  # empty exception tracking:
  addSon(result, newNode(nkEmpty))
  # body:
  addSon(result, newTree(nkStmtList, if w.wrapInObject != nil: w.wrapInObject else: w.call))
  if w.useful or w.wrapInObject != nil:
    c.m.add result

proc pp(c: var Context; n: PNode) =
  case n.kind
  of nkTypeSection:
    for i in 0 ..< n.len:
      if n[i].kind == nkTypeDef:
        handleObjectDecl(c, n[i], n[i].lastSon)
  of nkProcDef:
    handleProc(c, n)
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
