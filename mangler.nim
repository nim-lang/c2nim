#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## Implements support for name mangling.

const skDontMangle = skUnknown

proc `=~`(s: string, a: openArray[string]): bool =
  for x in a:
    if s.startsWith(x): return true

proc nep1(s: string, k: TSymKind): string =
  let allUpper = allCharsInSet(s, {'A'..'Z', '0'..'9', '_'})
  if allUpper and k in {skConst, skEnumField, skVar}:
    return s
  var L = s.len
  while L > 0 and s[L-1] == '_': dec L
  result = newStringOfCap(L)
  var i = 0
  while i < L and s[i] == '_': inc i
  case k
  of skType, skGenericParam:
    # Types should start with a capital unless builtins like 'int' etc.:
    if s =~ ["int", "uint", "cint", "cuint", "clong", "cstring", "string",
             "char", "byte", "bool", "openArray", "seq", "array", "void",
             "pointer", "float", "csize_t", "cdouble", "cchar", "cschar",
             "cshort", "cu", "nil", "expr", "stmt", "typedesc", "auto", "any",
             "range", "openarray", "varargs", "set", "cfloat"]:
      result.add s[i]
    else:
      result.add toUpperAscii(s[i])
  of skConst, skEnumField:
    # for 'const' we keep how it's spelt; either upper case or lower case:
    result.add s[i]
  else:
    # as a special rule, don't transform 'L' to 'l'
    if L == 1 and s[L-1] == 'L': result.add 'L'
    else:
      result.add toLowerAscii(s[i])
  inc i
  while i < L:
    if s[i] == '_':
      let before = i-1
      while i < L and s[i] == '_': inc i
      if before >= 0 and s[before] in {'A'..'Z'}:
        # don't skip '_' as it's essential for e.g. 'GC_disable'
        result.add('_')
        result.add s[i]
      else:
        result.add toUpperAscii(s[i])
    elif allUpper:
      result.add toLowerAscii(s[i])
    else:
      result.add s[i]
    inc i

proc mangleRules(s: string, p: Parser; kind: TSymKind): string =
  block mangle:
    for pattern, frmt in items(p.options.mangleRules):
      if s.match(pattern):
        result = s.replacef(pattern, frmt)
        break mangle
    block prefixes:
      for prefix in items(p.options.prefixes):
        if s.startsWith(prefix):
          result = s.substr(prefix.len)
          break prefixes
      result = s
    block suffixes:
      for suffix in items(p.options.suffixes):
        if result.endsWith(suffix):
          setLen(result, result.len - suffix.len)
          break suffixes
    if p.options.followNep1 and kind != skDontMangle:
      result = nep1(result, kind)

proc mangleName(s: string, p: Parser; kind: TSymKind): string =
  if p.options.toMangle.hasKey(s): result = p.options.toMangle[s]
  else: result = mangleRules(s, p, kind)

proc isPrivate(s: string, p: Parser): bool =
  for pattern in items(p.options.privateRules):
    if s.match(pattern): return true

proc mangledIdent(ident: string, p: Parser; kind: TSymKind): PNode =
  result = newNodeP(nkIdent, p)
  result.ident = getIdent(mangleName(ident, p, kind))

proc getHeaderPair(p: Parser): PNode =
  let pre = p.options.headerPrefix
  if p.options.headerOverride.len > 0:
    newIdentPair("header", pre & p.options.headerOverride, p)
  else:
    newIdentStrLitPair("header", pre & p.header, p)

proc addImportToPragma(pragmas: PNode, ident: string, p: Parser) =
  if pfImportc in p.options.flags:
    discard # already added importc pragma
  else:
    addSon(pragmas, newIdentStrLitPair(p.options.importcLit, p.currentNamespace & ident, p))
  if p.options.dynlibSym.len > 0:
    addSon(pragmas, newIdentPair("dynlib", p.options.dynlibSym, p))
  else:
    addSon(pragmas, getHeaderPair(p))

proc exportSym(p: Parser, i: PNode, origName: string): PNode =
  assert i.kind in {nkIdent, nkAccQuoted}
  if p.scopeCounter == 0 and not isPrivate(origName, p):
    result = newNodeI(nkPostfix, i.info)
    addSon(result, newIdentNode(getIdent("*"), i.info), i)
  else:
    result = i

proc varIdent(ident: string, p: Parser; section: TNodeKind): PNode =
  result = exportSym(p, mangledIdent(ident, p, skVar), ident)
  # a 'const' cannot be importcpp'ed:
  if p.scopeCounter > 0 or section == nkConstSection: return
  if p.options.dynlibSym.len > 0 or p.options.useHeader:
    var a = result
    result = newNodeP(nkPragmaExpr, p)
    var pragmas = newNodeP(nkPragma, p)
    addSon(result, a)
    addSon(result, pragmas)
    addImportToPragma(pragmas, ident, p)

proc fieldIdent(ident: string, p: Parser): PNode =
  result = exportSym(p, mangledIdent(ident, p, skField), ident)
  if p.scopeCounter > 0: return
  if p.options.useHeader:
    var a = result
    result = newNodeP(nkPragmaExpr, p)
    var pragmas = newNodeP(nkPragma, p)
    addSon(result, a)
    addSon(result, pragmas)
    addSon(pragmas, newIdentStrLitPair("importc", ident, p))

proc doImport(ident: string, pragmas: PNode, p: Parser) =
  if p.options.dynlibSym.len > 0 or p.options.useHeader:
    addImportToPragma(pragmas, p.currentNamespace & ident, p)

proc doImportCpp(ident: string, pragmas: PNode, p: Parser) =
  if p.options.dynlibSym.len > 0 or p.options.useHeader:
    addSon(pragmas, newIdentStrLitPair("importcpp", ident, p))
    if p.options.dynlibSym.len > 0:
      addSon(pragmas, newIdentPair("dynlib", p.options.dynlibSym, p))
    else:
      addSon(pragmas, getHeaderPair(p))
