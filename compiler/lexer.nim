#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# This lexer is handwritten for efficiency. I used an elegant buffering
# scheme which I have not seen anywhere else:
# We guarantee that a whole line is in the buffer. Thus only when scanning
# the \n or \r character we have to check whether we need to read in the next
# chunk. (\n or \r already need special handling for incrementing the line
# counter; choosing both \n and \r allows the lexer to properly read Unix,
# DOS or Macintosh text files, even when it is not the native format.

import idents

const
  MaxLineLength* = 80         # lines longer than this lead to a warning
  numChars*: set[char] = {'0'..'9', 'a'..'z', 'A'..'Z'}
  SymChars*: set[char] = {'a'..'z', 'A'..'Z', '0'..'9', '\x80'..'\xFF'}
  SymStartChars*: set[char] = {'a'..'z', 'A'..'Z', '\x80'..'\xFF'}
  OpChars*: set[char] = {'+', '-', '*', '/', '\\', '<', '>', '!', '?', '^', '.',
    '|', '=', '%', '&', '$', '@', '~', ':'}

type
  TokType* = enum
    tkInvalid = "tkInvalid", tkEof = "[EOF]", # order is important here!
    tkSymbol = "tkSymbol", # keywords:
    tkAddr = "addr", tkAnd = "and", tkAs = "as", tkAsm = "asm",
    tkBind = "bind", tkBlock = "block", tkBreak = "break", tkCase = "case", tkCast = "cast",
    tkConcept = "concept", tkConst = "const", tkContinue = "continue", tkConverter = "converter",
    tkDefer = "defer", tkDiscard = "discard", tkDistinct = "distinct", tkDiv = "div", tkDo = "do",
    tkElif = "elif", tkElse = "else", tkEnd = "end", tkEnum = "enum", tkExcept = "except", tkExport = "export",
    tkFinally = "finally", tkFor = "for", tkFrom = "from", tkFunc = "func",
    tkIf = "if", tkImport = "import", tkIn = "in", tkInclude = "include", tkInterface = "interface",
    tkIs = "is", tkIsnot = "isnot", tkIterator = "iterator",
    tkLet = "let",
    tkMacro = "macro", tkMethod = "method", tkMixin = "mixin", tkMod = "mod", tkNil = "nil", tkNot = "not", tkNotin = "notin",
    tkObject = "object", tkOf = "of", tkOr = "or", tkOut = "out",
    tkProc = "proc", tkPtr = "ptr", tkRaise = "raise", tkRef = "ref", tkReturn = "return",
    tkShl = "shl", tkShr = "shr", tkStatic = "static",
    tkTemplate = "template",
    tkTry = "try", tkTuple = "tuple", tkType = "type", tkUsing = "using",
    tkVar = "var", tkWhen = "when", tkWhile = "while", tkXor = "xor",
    tkYield = "yield", # end of keywords

    tkIntLit = "tkIntLit", tkInt8Lit = "tkInt8Lit", tkInt16Lit = "tkInt16Lit",
    tkInt32Lit = "tkInt32Lit", tkInt64Lit = "tkInt64Lit",
    tkUIntLit = "tkUIntLit", tkUInt8Lit = "tkUInt8Lit", tkUInt16Lit = "tkUInt16Lit",
    tkUInt32Lit = "tkUInt32Lit", tkUInt64Lit = "tkUInt64Lit",
    tkFloatLit = "tkFloatLit", tkFloat32Lit = "tkFloat32Lit",
    tkFloat64Lit = "tkFloat64Lit", tkFloat128Lit = "tkFloat128Lit",
    tkStrLit = "tkStrLit", tkRStrLit = "tkRStrLit", tkTripleStrLit = "tkTripleStrLit",
    tkGStrLit = "tkGStrLit", tkGTripleStrLit = "tkGTripleStrLit", tkCharLit = "tkCharLit",
    tkCustomLit = "tkCustomLit",

    tkParLe = "(", tkParRi = ")", tkBracketLe = "[",
    tkBracketRi = "]", tkCurlyLe = "{", tkCurlyRi = "}",
    tkBracketDotLe = "[.", tkBracketDotRi = ".]",
    tkCurlyDotLe = "{.", tkCurlyDotRi = ".}",
    tkParDotLe = "(.", tkParDotRi = ".)",
    tkComma = ",", tkSemiColon = ";",
    tkColon = ":", tkColonColon = "::", tkEquals = "=",
    tkDot = ".", tkDotDot = "..", tkBracketLeColon = "[:",
    tkOpr, tkComment, tkAccent = "`",
    # these are fake tokens used by renderer.nim
    tkSpaces, tkInfixOpr, tkPrefixOpr, tkPostfixOpr, tkHideableStart, tkHideableEnd

  TokTypes* = set[TokType]

const
  tokKeywordLow* = succ(tkSymbol)
  tokKeywordHigh* = pred(tkIntLit)

type
  NumericalBase* = enum
    base10,                   # base10 is listed as the first element,
                              # so that it is the correct default value
    base2, base8, base16

  Token* = object             # a Nim token
    tokType*: TokType         # the type of the token
    indent*: int              # the indentation; != -1 if the token has been
                              # preceded with indentation
    ident*: PIdent            # the parsed identifier
    iNumber*: BiggestInt      # the parsed integer literal
    fNumber*: BiggestFloat    # the parsed floating point literal
    base*: NumericalBase      # the numerical base; only valid for int
                              # or float literals
    strongSpaceA*: int8       # leading spaces of an operator
    strongSpaceB*: int8       # trailing spaces of an operator
    literal*: string          # the parsed (string) literal; and
                              # documentation comments are here too
    line*, col*: int

proc initToken*(L: var Token) =
  L.tokType = tkInvalid
  L.iNumber = 0
  L.indent = 0
  L.strongSpaceA = 0
  L.literal = ""
  L.fNumber = 0.0
  L.base = base10
  L.ident = nil

const
  UnicodeOperatorStartChars = {'\226', '\194', '\195'}
    # the allowed unicode characters ("∙ ∘ × ★ ⊗ ⊘ ⊙ ⊛ ⊠ ⊡ ∩ ∧ ⊓ ± ⊕ ⊖ ⊞ ⊟ ∪ ∨ ⊔")
    # all start with one of these.

type
  UnicodeOprPred = enum
    Mul, Add

proc unicodeOprLen(buf: cstring; pos: int): (int8, UnicodeOprPred) =
  template m(len): untyped = (int8(len), Mul)
  template a(len): untyped = (int8(len), Add)
  result = 0.m
  case buf[pos]
  of '\226':
    if buf[pos+1] == '\136':
      if buf[pos+2] == '\152': result = 3.m # ∘
      elif buf[pos+2] == '\153': result = 3.m # ∙
      elif buf[pos+2] == '\167': result = 3.m # ∧
      elif buf[pos+2] == '\168': result = 3.a # ∨
      elif buf[pos+2] == '\169': result = 3.m # ∩
      elif buf[pos+2] == '\170': result = 3.a # ∪
    elif buf[pos+1] == '\138':
      if buf[pos+2] == '\147': result = 3.m # ⊓
      elif buf[pos+2] == '\148': result = 3.a # ⊔
      elif buf[pos+2] == '\149': result = 3.a # ⊕
      elif buf[pos+2] == '\150': result = 3.a # ⊖
      elif buf[pos+2] == '\151': result = 3.m # ⊗
      elif buf[pos+2] == '\152': result = 3.m # ⊘
      elif buf[pos+2] == '\153': result = 3.m # ⊙
      elif buf[pos+2] == '\155': result = 3.m # ⊛
      elif buf[pos+2] == '\158': result = 3.a # ⊞
      elif buf[pos+2] == '\159': result = 3.a # ⊟
      elif buf[pos+2] == '\160': result = 3.m # ⊠
      elif buf[pos+2] == '\161': result = 3.m # ⊡
    elif buf[pos+1] == '\152' and buf[pos+2] == '\133': result = 3.m # ★
  of '\194':
    if buf[pos+1] == '\177': result = 2.a # ±
  of '\195':
    if buf[pos+1] == '\151': result = 2.m # ×
  else:
    discard

proc getPrecedence*(tok: Token): int =
  ## Calculates the precedence of the given token.
  const
    MulPred = 9
    PlusPred = 8
  case tok.tokType
  of tkOpr:
    let relevantChar = tok.ident.s[0]

    # arrow like?
    if tok.ident.s.len > 1 and tok.ident.s[^1] == '>' and
      tok.ident.s[^2] in {'-', '~', '='}: return 1

    template considerAsgn(value: untyped) =
      result = if tok.ident.s[^1] == '=': 1 else: value

    case relevantChar
    of '$', '^': considerAsgn(10)
    of '*', '%', '/', '\\': considerAsgn(MulPred)
    of '~': result = 8
    of '+', '-', '|': considerAsgn(PlusPred)
    of '&': considerAsgn(7)
    of '=', '<', '>', '!': result = 5
    of '.': considerAsgn(6)
    of '?': result = 2
    of UnicodeOperatorStartChars:
      if tok.ident.s[^1] == '=':
        result = 1
      else:
        let (len, pred) = unicodeOprLen(cstring(tok.ident.s), 0)
        if len != 0:
          result = if pred == Mul: MulPred else: PlusPred
        else:
          result = 2
    else: considerAsgn(2)
  of tkDiv, tkMod, tkShl, tkShr: result = 9
  of tkDotDot: result = 6
  of tkIn, tkNotin, tkIs, tkIsnot, tkOf, tkAs, tkFrom: result = 5
  of tkAnd: result = 4
  of tkOr, tkXor, tkPtr, tkRef: result = 3
  else: return -10

proc getPrecedence*(ident: PIdent): int =
  ## assumes ident is binary operator already
  var tok: Token
  initToken(tok)
  tok.ident = ident
  tok.tokType =
    if tok.ident.id in ord(tokKeywordLow) - ord(tkSymbol)..ord(tokKeywordHigh) - ord(tkSymbol):
      TokType(tok.ident.id + ord(tkSymbol))
    else: tkOpr
  getPrecedence(tok)
