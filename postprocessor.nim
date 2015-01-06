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

import ast, renderer

proc pp(n: var PNode) =
  if n.kind == nkIdent:
    if renderer.isKeyword(n.ident):
      let m = newNodeI(nkAccQuoted, n.info)
      m.add n
      n = m
  else:
    for i in 0.. < n.safeLen: pp(n.sons[i])

proc postprocess*(n: PNode): PNode =
  result = n
  pp(result)
