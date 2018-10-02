#
#
#      c2nim - C to Nim source converter
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This module implements an Ansi C scanner. This is an adaption from
# the scanner module. Keywords are not handled here, but in the parser to make
# it more flexible.


import strutils
import compiler / [options, msgs, platform, nimlexbase, llstream, nversion,
  idents]

when declared(NimCompilerApiVersion):
  import compiler / [lineinfos, pathutils]

const
  MaxLineLength* = 80         # lines longer than this lead to a warning
  numChars*: set[char] = {'0'..'9', 'a'..'z', 'A'..'Z'}
  SymChars*: set[char] = {'a'..'z', 'A'..'Z', '0'..'9', '_', '\x80'..'\xFF'}
  SymStartChars*: set[char] = {'a'..'z', 'A'..'Z', '_', '\x80'..'\xFF'}

type
  Tokkind* = enum
    pxInvalid, pxEof,
    pxMacroParam,             # fake token: macro parameter (with its index)
    pxMacroParamToStr,        # macro parameter (with its index) applied to the
                              # toString operator (#) in a #define: #param
    pxStarComment,            # /* */ comment
    pxLineComment,            # // comment
    pxDirective,              # #define, etc.
    pxDirectiveParLe,         # #define m( with parle (yes, C is that ugly!)
    pxDirConc,                # ##
    pxNewLine,                # newline: end of directive
    pxAmp,                    # &
    pxAmpAmp,                 # &&
    pxAmpAsgn,                # &=
    pxAmpAmpAsgn,             # &&=
    pxBar,                    # |
    pxBarBar,                 # ||
    pxBarAsgn,                # |=
    pxBarBarAsgn,             # ||=
    pxNot,                    # !
    pxPlusPlus,               # ++
    pxMinusMinus,             # --
    pxPlus,                   # +
    pxPlusAsgn,               # +=
    pxMinus,                  # -
    pxMinusAsgn,              # -=
    pxMod,                    # %
    pxModAsgn,                # %=
    pxSlash,                  # /
    pxSlashAsgn,              # /=
    pxStar,                   # *
    pxStarAsgn,               # *=
    pxHat,                    # ^
    pxHatAsgn,                # ^=
    pxAsgn,                   # =
    pxEquals,                 # ==
    pxDot,                    # .
    pxDotDotDot,              # ...
    pxLe,                     # <=
    pxLt,                     # <
    pxGe,                     # >=
    pxGt,                     # >
    pxNeq,                    # !=
    pxConditional,            # ?
    pxShl,                    # <<
    pxShlAsgn,                # <<=
    pxShr,                    # >>
    pxShrAsgn,                # >>=
    pxTilde,                  # ~
    pxTildeAsgn,              # ~=
    pxArrow,                  # ->
    pxArrowStar,              # ->*
    pxScope,                  # ::

    pxStrLit,
    pxCharLit,
    pxSymbol,                 # a symbol
    pxIntLit,
    pxInt64Lit, # long constant like 0x70fffffff or out of int range
    pxFloatLit,
    pxParLe, pxBracketLe, pxCurlyLe, # this order is important
    pxParRi, pxBracketRi, pxCurlyRi, # for macro argument parsing!
    pxComma, pxSemiColon, pxColon,
    pxAngleRi,                # '>' but determined to be the end of a
                              # template's angle bracket
    pxVerbatim                # #@ verbatim Nim code @#
  Tokkinds* = set[Tokkind]

type
  NumericalBase* = enum base10, base2, base8, base16
  Token* = object
    xkind*: Tokkind          # the type of the token
    s*: string                # parsed symbol, char or string literal
    iNumber*: BiggestInt      # the parsed integer literal;
                              # if xkind == pxMacroParam: parameter's position
    fNumber*: BiggestFloat    # the parsed floating point literal
    base*: NumericalBase     # the numerical base; only valid for int
                              # or float literals
    next*: ref Token         # for C we need arbitrary look-ahead :-(

  Lexer* = object of TBaseLexer
    fileIdx*: (when declared(FileIndex): FileIndex else: int32)
    inDirective, debugMode*: bool

var
  gLinesCompiled*: int

proc fillToken(L: var Token) =
  L.xkind = pxInvalid
  L.iNumber = 0
  L.s = ""
  L.fNumber = 0.0
  L.base = base10

when declared(NimCompilerApiVersion):
  var gConfig* = newConfigRef() # XXX make this part of the lexer
  var identCache* = newIdentCache()

  template toFilename*(idx: FileIndex): string = toFilename(gConfig, idx)

proc openLexer*(lex: var Lexer, filename: string, inputstream: PLLStream) =
  openBaseLexer(lex, inputstream)
  when declared(NimCompilerApiVersion):
    lex.fileIdx = fileInfoIdx(gConfig, AbsoluteFile filename)
  else:
    lex.fileIdx = filename.fileInfoIdx

proc closeLexer*(lex: var Lexer) =
  inc(gLinesCompiled, lex.lineNumber)
  closeBaseLexer(lex)

proc getColumn*(L: Lexer): int =
  result = getColNumber(L, L.bufPos)

proc getLineInfo*(L: Lexer): TLineInfo =
  result = newLineInfo(L.fileIdx, L.linenumber, getColNumber(L, L.bufpos))

proc lexMessage*(L: Lexer, msg: TMsgKind, arg = "") =
  if L.debugMode: writeStackTrace()
  when declared(NimCompilerApiVersion):
    msgs.globalError(gConfig, getLineInfo(L), msg, arg)
  else:
    msgs.globalError(getLineInfo(L), msg, arg)

proc lexMessagePos(L: var Lexer, msg: TMsgKind, pos: int, arg = "") =
  var info = newLineInfo(L.fileIdx, L.linenumber, pos - L.lineStart)
  if L.debugMode: writeStackTrace()
  when declared(NimCompilerApiVersion):
    msgs.globalError(gConfig, info, msg, arg)
  else:
    msgs.globalError(info, msg, arg)

proc tokKindToStr*(k: Tokkind): string =
  case k
  of pxEof: result = "[EOF]"
  of pxInvalid: result = "[invalid]"
  of pxMacroParam, pxMacroParamToStr: result = "[macro param]"
  of pxStarComment, pxLineComment: result = "[comment]"
  of pxStrLit: result = "[string literal]"
  of pxCharLit: result = "[char literal]"

  of pxDirective, pxDirectiveParLe: result = "#"             # #define, etc.
  of pxDirConc: result = "##"
  of pxNewLine: result = "[NewLine]"
  of pxAmp: result = "&"                   # &
  of pxAmpAmp: result = "&&"               # &&
  of pxAmpAsgn: result = "&="              # &=
  of pxAmpAmpAsgn: result = "&&="          # &&=
  of pxBar: result = "|"                   # |
  of pxBarBar: result = "||"               # ||
  of pxBarAsgn: result = "|="              # |=
  of pxBarBarAsgn: result = "||="          # ||=
  of pxNot: result = "!"                   # !
  of pxPlusPlus: result = "++"             # ++
  of pxMinusMinus: result = "--"           # --
  of pxPlus: result = "+"                  # +
  of pxPlusAsgn: result = "+="             # +=
  of pxMinus: result = "-"                 # -
  of pxMinusAsgn: result = "-="            # -=
  of pxMod: result = "%"                   # %
  of pxModAsgn: result = "%="              # %=
  of pxSlash: result = "/"                 # /
  of pxSlashAsgn: result = "/="            # /=
  of pxStar: result = "*"                  # *
  of pxStarAsgn: result = "*="             # *=
  of pxHat: result = "^"                   # ^
  of pxHatAsgn: result = "^="              # ^=
  of pxAsgn: result = "="                  # =
  of pxEquals: result = "=="               # ==
  of pxDot: result = "."                   # .
  of pxDotDotDot: result = "..."           # ...
  of pxLe: result = "<="                   # <=
  of pxLt: result = "<"                    # <
  of pxGe: result = ">="                   # >=
  of pxGt: result = ">"                    # >
  of pxNeq: result = "!="                  # !=
  of pxConditional: result = "?"
  of pxShl: result = "<<"
  of pxShlAsgn: result = "<<="
  of pxShr: result = ">>"
  of pxShrAsgn: result = ">>="
  of pxTilde: result = "~"
  of pxTildeAsgn: result = "~="
  of pxArrow: result = "->"
  of pxArrowStar: result = "->*"
  of pxScope: result = "::"

  of pxSymbol: result = "[identifier]"
  of pxIntLit, pxInt64Lit: result = "[integer literal]"
  of pxFloatLit: result = "[floating point literal]"
  of pxParLe: result = "("
  of pxParRi: result = ")"
  of pxBracketLe: result = "["
  of pxBracketRi: result = "]"
  of pxComma: result = ","
  of pxSemiColon: result = ";"
  of pxColon: result = ":"
  of pxCurlyLe: result = "{"
  of pxCurlyRi: result = "}"
  of pxAngleRi: result = "> [end of template]"
  of pxVerbatim: result = "#@ verbatim Nim code @#"

proc `$`*(tok: Token): string =
  case tok.xkind
  of pxSymbol, pxInvalid, pxStarComment, pxLineComment, pxStrLit: result = tok.s
  of pxIntLit, pxInt64Lit: result = $tok.iNumber
  of pxFloatLit: result = $tok.fNumber
  else: result = tokKindToStr(tok.xkind)

proc debugTok*(L: Lexer; tok: Token): string =
  result = $tok
  if L.debugMode: result.add(" (" & $tok.xkind & ")")

proc printTok*(tok: Token) =
  writeLine(stdout, $tok)

proc matchUnderscoreChars(L: var Lexer, tok: var Token, chars: set[char]) =
  # matches ([chars]_)*
  var pos = L.bufpos              # use registers for pos, buf
  var buf = L.buf
  while true:
    if buf[pos] in chars:
      add(tok.s, buf[pos])
      inc(pos)
    else:
      break
    if buf[pos] == '_':
      add(tok.s, '_')
      inc(pos)
  L.bufPos = pos

proc isFloatLiteral(s: string): bool =
  for i in countup(0, len(s)-1):
    if s[i] in {'.', 'e', 'E'}:
      return true

proc getNumber2(L: var Lexer, tok: var Token) =
  var pos = L.bufpos + 2 # skip 0b
  tok.base = base2
  var xi: BiggestInt = 0
  var bits = 0
  while true:
    case L.buf[pos]
    of 'A'..'Z', 'a'..'z':
      # ignore type suffix:
      inc(pos)
    of '2'..'9', '.':
      when declared(errInvalidNumber):
        lexMessage(L, errInvalidNumber)
      else:
        lexMessage(L, errGenerated, "invalid number")
      inc(pos)
    of '_':
      inc(pos)
    of '0', '1':
      xi = `shl`(xi, 1) or (ord(L.buf[pos]) - ord('0'))
      inc(pos)
      inc(bits)
    else: break
  tok.iNumber = xi
  if (bits > 32): tok.xkind = pxInt64Lit
  else: tok.xkind = pxIntLit
  L.bufpos = pos

proc getNumber8(L: var Lexer, tok: var Token) =
  var pos = L.bufpos + 1 # skip 0
  tok.base = base8
  var xi: BiggestInt = 0
  var bits = 0
  while true:
    case L.buf[pos]
    of 'A'..'Z', 'a'..'z':
      # ignore type suffix:
      inc(pos)
    of '8'..'9', '.':
      when declared(errInvalidNumber):
        lexMessage(L, errInvalidNumber)
      else:
        lexMessage(L, errGenerated, "invalid number")
      inc(pos)
    of '_':
      inc(pos)
    of '0'..'7':
      xi = `shl`(xi, 3) or (ord(L.buf[pos]) - ord('0'))
      inc(pos)
      inc(bits)
    else: break
  tok.iNumber = xi
  if (bits > 12): tok.xkind = pxInt64Lit
  else: tok.xkind = pxIntLit
  L.bufpos = pos

proc getNumber16(L: var Lexer, tok: var Token) =
  var pos = L.bufpos + 2          # skip 0x
  tok.base = base16
  var xi: BiggestInt = 0
  var bits = 0
  while true:
    case L.buf[pos]
    of 'G'..'Z', 'g'..'z':
      # ignore type suffix:
      inc(pos)
    of '_': inc(pos)
    of '0'..'9':
      xi = `shl`(xi, 4) or (ord(L.buf[pos]) - ord('0'))
      inc(pos)
      inc(bits, 4)
    of 'a'..'f':
      xi = `shl`(xi, 4) or (ord(L.buf[pos]) - ord('a') + 10)
      inc(pos)
      inc(bits, 4)
    of 'A'..'F':
      xi = `shl`(xi, 4) or (ord(L.buf[pos]) - ord('A') + 10)
      inc(pos)
      inc(bits, 4)
    else: break
  tok.iNumber = xi
  if bits > 32: tok.xkind = pxInt64Lit
  else: tok.xkind = pxIntLit
  L.bufpos = pos

proc getFloating(L: var Lexer, tok: var Token) =
  matchUnderscoreChars(L, tok, {'0'..'9'})
  if L.buf[L.bufpos] in {'e', 'E'}:
    add(tok.s, L.buf[L.bufpos])
    inc(L.bufpos)
    if L.buf[L.bufpos] in {'+', '-'}:
      add(tok.s, L.buf[L.bufpos])
      inc(L.bufpos)
    matchUnderscoreChars(L, tok, {'0'..'9'})

proc getNumber(L: var Lexer, tok: var Token) =
  tok.base = base10
  if L.buf[L.bufpos] == '.':
    add(tok.s, "0.")
    inc(L.bufpos)
    getFloating(L, tok)
  else:
    matchUnderscoreChars(L, tok, {'0'..'9'})
    if L.buf[L.bufpos] in {'.','e','E'}:
      if L.buf[L.bufpos] == '.':
        add(tok.s, L.buf[L.bufpos])
        inc(L.bufpos)
      getFloating(L, tok)
  try:
    if isFloatLiteral(tok.s):
      tok.fnumber = parseFloat(tok.s)
      tok.xkind = pxFloatLit
    else:
      tok.iNumber = parseInt(tok.s)
      if (tok.iNumber < low(int32)) or (tok.iNumber > high(int32)):
        tok.xkind = pxInt64Lit
      else:
        tok.xkind = pxIntLit
  except ValueError:
    lexMessage(L, errGenerated, "invalid number: " & tok.s)
  except OverflowError:
    lexMessage(L, errGenerated, "number out of range: " & tok.s)
  # ignore type suffix:
  while L.buf[L.bufpos] in {'A'..'Z', 'a'..'z'}: inc(L.bufpos)

proc handleCRLF(L: var Lexer, pos: int): int =
  case L.buf[pos]
  of CR: result = nimlexbase.handleCR(L, pos)
  of LF: result = nimlexbase.handleLF(L, pos)
  else: result = pos

proc escape(L: var Lexer, tok: var Token, allowEmpty=false) =
  inc(L.bufpos) # skip \
  case L.buf[L.bufpos]
  of 'b', 'B':
    add(tok.s, '\b')
    inc(L.bufpos)
  of 't', 'T':
    add(tok.s, '\t')
    inc(L.bufpos)
  of 'n', 'N':
    add(tok.s, '\L')
    inc(L.bufpos)
  of 'f', 'F':
    add(tok.s, '\f')
    inc(L.bufpos)
  of 'r', 'R':
    add(tok.s, '\r')
    inc(L.bufpos)
  of '\'':
    add(tok.s, '\'')
    inc(L.bufpos)
  of '"':
    add(tok.s, '"')
    inc(L.bufpos)
  of '\\':
    add(tok.s, '\b')
    inc(L.bufpos)
  of '0'..'7':
    var xi = ord(L.buf[L.bufpos]) - ord('0')
    inc(L.bufpos)
    if L.buf[L.bufpos] in {'0'..'7'}:
      xi = (xi shl 3) or (ord(L.buf[L.bufpos]) - ord('0'))
      inc(L.bufpos)
      if L.buf[L.bufpos] in {'0'..'7'}:
        xi = (xi shl 3) or (ord(L.buf[L.bufpos]) - ord('0'))
        inc(L.bufpos)
    add(tok.s, chr(xi))
  of 'x':
    var xi = 0
    inc(L.bufpos)
    while true:
      case L.buf[L.bufpos]
      of '0'..'9':
        xi = `shl`(xi, 4) or (ord(L.buf[L.bufpos]) - ord('0'))
        inc(L.bufpos)
      of 'a'..'f':
        xi = `shl`(xi, 4) or (ord(L.buf[L.bufpos]) - ord('a') + 10)
        inc(L.bufpos)
      of 'A'..'F':
        xi = `shl`(xi, 4) or (ord(L.buf[L.bufpos]) - ord('A') + 10)
        inc(L.bufpos)
      else:
        break
    add(tok.s, chr(xi))
  elif not allowEmpty:
    lexMessage(L, errGenerated, "invalid character constant")

proc getCharLit(L: var Lexer, tok: var Token) =
  inc(L.bufpos) # skip '
  if L.buf[L.bufpos] == '\\':
    escape(L, tok)
  else:
    add(tok.s, L.buf[L.bufpos])
    inc(L.bufpos)
  if L.buf[L.bufpos] == '\'':
    inc(L.bufpos)
  else:
    lexMessage(L, errGenerated, "missing closing single quote")
  tok.xkind = pxCharLit

proc getString(L: var Lexer, tok: var Token) =
  var pos = L.bufPos + 1          # skip "
  var buf = L.buf                 # put `buf` in a register
  var line = L.linenumber         # save linenumber for better error message
  while true:
    case buf[pos]
    of '\"':
      inc(pos)
      break
    of CR:
      pos = nimlexbase.handleCR(L, pos)
      buf = L.buf
    of LF:
      pos = nimlexbase.handleLF(L, pos)
      buf = L.buf
    of nimlexbase.EndOfFile:
      var line2 = L.linenumber
      L.lineNumber = line
      lexMessagePos(L, errGenerated, L.lineStart, "closing \" expected, but end of file reached")
      L.lineNumber = line2
      break
    of '\\':
      # we allow an empty \ for line concatenation, but we don't require it
      # for line concatenation
      L.bufpos = pos
      escape(L, tok, allowEmpty=true)
      pos = L.bufpos
    else:
      add(tok.s, buf[pos])
      inc(pos)
  L.bufpos = pos
  tok.xkind = pxStrLit

proc getSymbol(L: var Lexer, tok: var Token) =
  var pos = L.bufpos
  var buf = L.buf
  while true:
    var c = buf[pos]
    if c notin SymChars: break
    add(tok.s, c)
    inc(pos)
  L.bufpos = pos
  tok.xkind = pxSymbol

proc scanLineComment(L: var Lexer, tok: var Token) =
  var pos = L.bufpos
  var buf = L.buf
  # a comment ends if the next line does not start with the // on the same
  # column after only whitespace
  tok.xkind = pxLineComment
  var col = getColNumber(L, pos)
  while true:
    inc(pos, 2)               # skip //
    #add(tok.s, '#')
    while buf[pos] notin {CR, LF, nimlexbase.EndOfFile}:
      add(tok.s, buf[pos])
      inc(pos)
    pos = handleCRLF(L, pos)
    buf = L.buf
    var indent = 0
    while buf[pos] == ' ':
      inc(pos)
      inc(indent)
    if col == indent and buf[pos] == '/' and buf[pos+1] == '/':
      add(tok.s, "\n")
    else:
      break
  while tok.s.len > 0 and tok.s[^1] in {'\t', ' '}: setLen(tok.s, tok.s.len-1)
  L.bufpos = pos

proc scanStarComment(L: var Lexer, tok: var Token) =
  var pos = L.bufpos
  var buf = L.buf
  tok.s = ""
  tok.xkind = pxStarComment
  while true:
    case buf[pos]
    of CR, LF:
      pos = handleCRLF(L, pos)
      buf = L.buf
      add(tok.s, "\n")
      # skip annoying stars as line prefix: (eg.
      # /*
      #  * ugly comment <-- this star
      #  */
      let oldPos = pos
      while buf[pos] in {' ', '\t'}:
        #add(tok.s, ' ')
        inc(pos)
      if buf[pos] == '*':
        if buf[pos+1] != '/':
          inc(pos)
        else:
          inc(pos, 2)
          break
      else: pos = oldPos
    of '*':
      inc(pos)
      if buf[pos] == '/':
        inc(pos)
        break
      else:
        add(tok.s, '*')
    of nimlexbase.EndOfFile:
      lexMessage(L, errGenerated, "expected closing '*/'")
    else:
      add(tok.s, buf[pos])
      inc(pos)
  # strip trailing whitespace
  while tok.s.len > 0 and tok.s[^1] in {'\t', ' '}: setLen(tok.s, tok.s.len-1)
  L.bufpos = pos

proc scanVerbatim(L: var Lexer, tok: var Token; isCurlyDot: bool) =
  var pos = L.bufpos+2
  var buf = L.buf
  while buf[pos] in {' ', '\t'}: inc(pos)
  if buf[pos] in {CR, LF}:
    pos = handleCRLF(L, pos)
    buf = L.buf
  tok.xkind = pxVerbatim
  tok.s = ""
  while true:
    case buf[pos]
    of CR, LF:
      pos = handleCRLF(L, pos)
      buf = L.buf
      var lookahead = pos
      while buf[lookahead] in {' ', '\t'}: inc(lookahead)
      if buf[lookahead] == '@' and buf[lookahead+1] == '#':
        pos = lookahead+2
        break
      add(tok.s, "\n")
    of nimlexbase.EndOfFile:
      lexMessage(L, errGenerated, "expected closing '@#'")
    of '.':
      if isCurlyDot and buf[pos+1] == '}':
        inc pos, 2
        break
      add(tok.s, buf[pos])
      inc(pos)
    else:
      add(tok.s, buf[pos])
      inc(pos)
  L.bufpos = pos

proc skip(L: var Lexer, tok: var Token) =
  var pos = L.bufpos
  var buf = L.buf
  while true:
    case buf[pos]
    of '\\':
      # Ignore \ line continuation characters when not inDirective
      inc(pos)
      if L.inDirective:
        while buf[pos] in {' ', '\t'}: inc(pos)
        if buf[pos] in {CR, LF}:
          pos = handleCRLF(L, pos)
          buf = L.buf
    of ' ', Tabulator:
      inc(pos)                # newline is special:
    of CR, LF:
      pos = handleCRLF(L, pos)
      buf = L.buf
      if L.inDirective:
        tok.xkind = pxNewLine
        L.inDirective = false
    else:
      break                   # EndOfFile also leaves the loop
  L.bufpos = pos

proc getDirective(L: var Lexer, tok: var Token) =
  var pos = L.bufpos + 1
  var buf = L.buf
  while buf[pos] in {' ', '\t'}: inc(pos)
  while buf[pos] in SymChars:
    add(tok.s, buf[pos])
    inc(pos)
  # a HACK: we need to distinguish
  # #define x (...)
  # from:
  # #define x(...)
  #
  L.bufpos = pos
  # look ahead:
  while buf[pos] in {' ', '\t'}: inc(pos)
  while buf[pos] in SymChars: inc(pos)
  if buf[pos] == '(': tok.xkind = pxDirectiveParLe
  else: tok.xkind = pxDirective
  L.inDirective = true

proc getTok*(L: var Lexer, tok: var Token) =
  tok.xkind = pxInvalid
  fillToken(tok)
  skip(L, tok)
  if tok.xkind == pxNewLine: return
  var c = L.buf[L.bufpos]
  if c in SymStartChars:
    getSymbol(L, tok)
  elif c == '0':
    case L.buf[L.bufpos+1]
    of 'x', 'X': getNumber16(L, tok)
    of 'b', 'B': getNumber2(L, tok)
    of '1'..'7': getNumber8(L, tok)
    else: getNumber(L, tok)
  elif c in {'1'..'9'} or (c == '.' and L.buf[L.bufpos+1] in {'0'..'9'}):
    getNumber(L, tok)
  else:
    case c
    of ';':
      tok.xkind = pxSemicolon
      inc(L.bufpos)
    of '/':
      if L.buf[L.bufpos + 1] == '/':
        scanLineComment(L, tok)
      elif L.buf[L.bufpos+1] == '*':
        inc(L.bufpos, 2)
        scanStarComment(L, tok)
      elif L.buf[L.bufpos+1] == '=':
        inc(L.bufpos, 2)
        tok.xkind = pxSlashAsgn
      else:
        tok.xkind = pxSlash
        inc(L.bufpos)
    of ',':
      tok.xkind = pxComma
      inc(L.bufpos)
    of '(':
      inc(L.bufpos)
      tok.xkind = pxParLe
    of '*':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        inc(L.bufpos)
        tok.xkind = pxStarAsgn
      else:
        tok.xkind = pxStar
    of ')':
      inc(L.bufpos)
      tok.xkind = pxParRi
    of '[':
      inc(L.bufpos)
      tok.xkind = pxBracketLe
    of ']':
      inc(L.bufpos)
      tok.xkind = pxBracketRi
    of '.':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '.' and L.buf[L.bufpos+1] == '.':
        tok.xkind = pxDotDotDot
        inc(L.bufpos, 2)
      else:
        tok.xkind = pxDot
    of '{':
      if L.buf[L.bufpos+1] == '.':
        scanVerbatim(L, tok, true)
      else:
        inc(L.bufpos)
        tok.xkind = pxCurlyLe
    of '}':
      inc(L.bufpos)
      tok.xkind = pxCurlyRi
    of '+':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        tok.xkind = pxPlusAsgn
        inc(L.bufpos)
      elif L.buf[L.bufpos] == '+':
        tok.xkind = pxPlusPlus
        inc(L.bufpos)
      else:
        tok.xkind = pxPlus
    of '-':
      inc(L.bufpos)
      case L.buf[L.bufpos]
      of '>':
        tok.xkind = pxArrow
        inc(L.bufpos)
        if L.buf[L.bufpos] == '*':
          tok.xkind = pxArrowStar
          inc(L.bufpos)
      of '=':
        tok.xkind = pxMinusAsgn
        inc(L.bufpos)
      of '-':
        tok.xkind = pxMinusMinus
        inc(L.bufpos)
      else:
        tok.xkind = pxMinus
    of '?':
      inc(L.bufpos)
      tok.xkind = pxConditional
    of ':':
      inc(L.bufpos)
      if L.buf[L.bufpos] == ':':
        tok.xkind = pxScope
        inc(L.bufpos)
      else:
        tok.xkind = pxColon
    of '!':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        tok.xkind = pxNeq
        inc(L.bufpos)
      else:
        tok.xkind = pxNot
    of '<':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        inc(L.bufpos)
        tok.xkind = pxLe
      elif L.buf[L.bufpos] == '<':
        inc(L.bufpos)
        if L.buf[L.bufpos] == '=':
          inc(L.bufpos)
          tok.xkind = pxShlAsgn
        else:
          tok.xkind = pxShl
      else:
        tok.xkind = pxLt
    of '>':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        inc(L.bufpos)
        tok.xkind = pxGe
      elif L.buf[L.bufpos] == '>':
        inc(L.bufpos)
        if L.buf[L.bufpos] == '=':
          inc(L.bufpos)
          tok.xkind = pxShrAsgn
        else:
          tok.xkind = pxShr
      else:
        tok.xkind = pxGt
    of '=':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        tok.xkind = pxEquals
        inc(L.bufpos)
      else:
        tok.xkind = pxAsgn
    of '&':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        tok.xkind = pxAmpAsgn
        inc(L.bufpos)
      elif L.buf[L.bufpos] == '&':
        inc(L.bufpos)
        if L.buf[L.bufpos] == '=':
          inc(L.bufpos)
          tok.xkind = pxAmpAmpAsgn
        else:
          tok.xkind = pxAmpAmp
      else:
        tok.xkind = pxAmp
    of '|':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        tok.xkind = pxBarAsgn
        inc(L.bufpos)
      elif L.buf[L.bufpos] == '|':
        inc(L.bufpos)
        if L.buf[L.bufpos] == '=':
          inc(L.bufpos)
          tok.xkind = pxBarBarAsgn
        else:
          tok.xkind = pxBarBar
      else:
        tok.xkind = pxBar
    of '^':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        tok.xkind = pxHatAsgn
        inc(L.bufpos)
      else:
        tok.xkind = pxHat
    of '%':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        tok.xkind = pxModAsgn
        inc(L.bufpos)
      else:
        tok.xkind = pxMod
    of '~':
      inc(L.bufpos)
      if L.buf[L.bufpos] == '=':
        tok.xkind = pxTildeAsgn
        inc(L.bufpos)
      else:
        tok.xkind = pxTilde
    of '#':
      if L.buf[L.bufpos+1] == '#':
        inc(L.bufpos, 2)
        tok.xkind = pxDirConc
      elif L.buf[L.bufpos+1] == '@':
        scanVerbatim(L, tok, false)
      else:
        getDirective(L, tok)
    of '"': getString(L, tok)
    of '\'': getCharLit(L, tok)
    of nimlexbase.EndOfFile:
      tok.xkind = pxEof
    else:
      tok.s = $c
      tok.xkind = pxInvalid
      lexMessage(L, errGenerated, "invalid token " & c & " (\\" & $(ord(c)) & ')')
      inc(L.bufpos)
