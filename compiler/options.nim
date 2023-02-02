#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import std/[os, strutils, sets, tables]
import lineinfos, pathutils

from times import utc, fromUnix, local, getTime, format, DateTime

const
  hasFFI* = defined(nimHasLibFFI)
  copyrightYear* = "2022"

type                          # please make sure we have under 32 options
                              # (improves code efficiency a lot!)
  TOption* = enum             # **keep binary compatible**
    optNone, optStyleCheck,
    optAssert, optLineDir, optWarns, optHints,
    optByRef,                 # use pass by ref for objects
                              # (for interfacing with C)

  TOptions* = set[TOption]
  TGlobalOption* = enum
    gloptNone, optForceFullMake,
    optStyleHint,             # check that the names adhere to NEP-1
    optStyleError,            # enforce that the names adhere to NEP-1
    optStyleUsages,           # only enforce consistent **usages** of the symbol
    optSkipParentConfigFiles, # skip parent dir's cfg/nims config files
    optUseColors,             # use colors for hints, warnings, and errors
    optStdout,                # output to stdout
    optGenIndex               # generate index file for documentation;
    optEmbedOrigSrc           # embed the original source in the generated code
                              # also: generate header file
    optIdeDebug               # idetools: debug mode
    optIdeTerse               # idetools: use terse descriptions
    optExcessiveStackTrace    # fully qualified module filenames
    optShowAllMismatches      # show all overloading resolution candidates
    optWholeProject           # for 'doc': output any dependency
    optDocInternal            # generate documentation for non-exported symbols
    optListFullPaths          # use full paths in toMsgFilename

  TGlobalOptions* = set[TGlobalOption]

const
  harmlessOptions* = {optForceFullMake, optUseColors, optStdout}
  genSubDir* = RelativeDir"nimcache"
  NimExt* = "nim"
  RodExt* = "rod"
  HtmlExt* = "html"
  JsonExt* = "json"
  TagsExt* = "tags"
  TexExt* = "tex"
  IniExt* = "ini"
  DefaultConfig* = RelativeFile"nim.cfg"
  DefaultConfigNims* = RelativeFile"config.nims"
  DocConfig* = RelativeFile"nimdoc.cfg"
  DocTexConfig* = RelativeFile"nimdoc.tex.cfg"
  docRootDefault* = "@default" # using `@` instead of `$` to avoid shell quoting complications
  oKeepVariableNames* = true

type
  ConfigRef* {.acyclic.} = ref object ## every global configuration
                          ## fields marked with '*' are subject to
                          ## the incremental compilation mechanisms
                          ## (+) means "part of the dependency"
    linesCompiled*: int   # all lines that have been compiled
    options*: TOptions    # (+)
    globalOptions*: TGlobalOptions # (+)
    m*: MsgConfig
    unitSep*: string
    exitcode*: int8
    verbosity*: int # how verbose the compiler is
    lastCmdTime*: float # when caas is enabled, we measure each command
    projectName*: string # holds a name like 'nim'
    projectPath*: AbsoluteDir # holds a path like /home/alice/projects/nim/compiler/
    projectFull*: AbsoluteFile # projectPath/projectName
    modifiedyNotes*: TNoteKinds # notes that have been set/unset from either cmdline/configs
    cmdlineNotes*: TNoteKinds # notes that have been set/unset from cmdline
    foreignPackageNotes*: TNoteKinds
    notes*: TNoteKinds # notes after resolving all logic(defaults, verbosity)/cmdline/configs
    mainPackageNotes*: TNoteKinds
    warningAsErrors*: TNoteKinds
    errorCounter*: int
    hintCounter*: int
    warnCounter*: int
    errorMax*: int
    writelnHook*: proc (output: string) {.closure.} # cannot make this gcsafe yet because of Nimble

proc assignIfDefault*[T](result: var T, val: T, def = default(T)) =
  ## if `result` was already assigned to a value (that wasn't `def`), this is a noop.
  if result == def: result = val

template setErrorMaxHighMaybe*(conf: ConfigRef) =
  ## do not stop after first error (but honor --errorMax if provided)
  assignIfDefault(conf.errorMax, high(int))

proc hasHint*(conf: ConfigRef, note: TNoteKind): bool =
  # ternary states instead of binary states would simplify logic
  if optHints notin conf.options: false
  elif note in {hintConf, hintProcessing}:
    # could add here other special notes like hintSource
    # these notes apply globally.
    note in conf.mainPackageNotes
  else: note in conf.notes

proc hasWarn*(conf: ConfigRef, note: TNoteKind): bool {.inline.} =
  optWarns in conf.options and note in conf.notes

const
  ChecksOptions* = {optStyleCheck}

  DefaultOptions* = {optAssert, optWarns, optHints, optStyleCheck}
  DefaultGlobalOptions*: TGlobalOptions = {}

proc getSrcTimestamp(): DateTime =
  try:
    result = utc(fromUnix(parseInt(getEnv("SOURCE_DATE_EPOCH",
                                          "not a number"))))
  except ValueError:
    # Environment variable malformed.
    # https://reproducible-builds.org/specs/source-date-epoch/: "If the
    # value is malformed, the build process SHOULD exit with a non-zero
    # error code", which this doesn't do. This uses local time, because
    # that maintains compatibility with existing usage.
    result = utc getTime()

proc getDateStr*(): string =
  result = format(getSrcTimestamp(), "yyyy-MM-dd")

proc getClockStr*(): string =
  result = format(getSrcTimestamp(), "HH:mm:ss")

const foreignPackageNotesDefault* = {
  hintProcessing, warnUnknownMagic, hintQuitCalled, hintExecuting, hintUser, warnUser}

proc initConfigRefCommon(conf: ConfigRef) =
  conf.verbosity = 1
  conf.options = DefaultOptions
  conf.globalOptions = DefaultGlobalOptions
  conf.foreignPackageNotes = foreignPackageNotesDefault
  conf.notes = NotesVerbosity[1]
  conf.mainPackageNotes = NotesVerbosity[1]

proc newPartialConfigRef*(): ConfigRef =
  ## create a new ConfigRef that is only good enough for error reporting.
  result = ConfigRef()
  initConfigRefCommon(result)

proc canonicalizePath*(conf: ConfigRef; path: AbsoluteFile): AbsoluteFile =
  result = AbsoluteFile path.string.expandFilename
