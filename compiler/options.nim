#
#
#           The Nim Compiler
#        (c) Copyright 2015 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

import
  os, strutils, strtabs, osproc, sets, lineinfos, pathutils

from terminal import isatty
from times import utc, fromUnix, local, getTime, format, DateTime

const
  hasTinyCBackend* = defined(tinyc)
  useEffectSystem* = true
  useWriteTracking* = false
  hasFFI* = defined(nimHasLibFFI)
  copyrightYear* = "2019"

type                          # please make sure we have under 32 options
                              # (improves code efficiency a lot!)
  TOption* = enum             # **keep binary compatible**
    optNone, optObjCheck, optFieldCheck, optRangeCheck, optBoundsCheck,
    optOverflowCheck, optNilCheck, optRefCheck,
    optNaNCheck, optInfCheck, optStyleCheck,
    optAssert, optLineDir, optWarns, optHints,
    optOptimizeSpeed, optOptimizeSize, optStackTrace, # stack tracing support
    optLineTrace,             # line tracing support (includes stack tracing)
    optEndb,                  # embedded debugger
    optByRef,                 # use pass by ref for objects
                              # (for interfacing with C)
    optProfiler,              # profiler turned on
    optImplicitStatic,        # optimization: implicit at compile time
                              # evaluation
    optTrMacros,              # en/disable pattern matching
    optMemTracker,
    optLaxStrings,
    optNilSeqs,
    optOldAst

  TOptions* = set[TOption]
  TGlobalOption* = enum       # **keep binary compatible**
    gloptNone, optForceFullMake,
    optWasNimscript,
    optListCmd, optCompileOnly, optNoLinking,
    optCDebug,                # turn on debugging information
    optGenDynLib,             # generate a dynamic library
    optGenStaticLib,          # generate a static library
    optGenGuiApp,             # generate a GUI application
    optGenScript,             # generate a script file to compile the *.c files
    optGenMapping,            # generate a mapping file
    optRun,                   # run the compiled project
    optStyleHint,             # check that the names adhere to NEP-1
    optStyleError,            # enforce that the names adhere to NEP-1
    optSkipSystemConfigFile,  # skip the system's cfg/nims config file
    optSkipProjConfigFile,    # skip the project's cfg/nims config file
    optSkipUserConfigFile,    # skip the users's cfg/nims config file
    optSkipParentConfigFiles, # skip parent dir's cfg/nims config files
    optNoMain,                # do not generate a "main" proc
    optUseColors,             # use colors for hints, warnings, and errors
    optThreads,               # support for multi-threading
    optStdout,                # output to stdout
    optThreadAnalysis,        # thread analysis pass
    optTaintMode,             # taint mode turned on
    optTlsEmulation,          # thread var emulation turned on
    optGenIndex               # generate index file for documentation;
    optEmbedOrigSrc           # embed the original source in the generated code
                              # also: generate header file
    optIdeDebug               # idetools: debug mode
    optIdeTerse               # idetools: use terse descriptions
    optNoCppExceptions        # use C exception handling even with CPP
    optExcessiveStackTrace    # fully qualified module filenames
    optShowAllMismatches      # show all overloading resolution candidates
    optWholeProject           # for 'doc2': output any dependency
    optDocInternal            # generate documentation for non-exported symbols
    optMixedMode              # true if some module triggered C++ codegen
    optListFullPaths          # use full paths in toMsgFilename
    optNoNimblePath
    optHotCodeReloading
    optDynlibOverrideAll
    optNimV2
    optMultiMethods

  TGlobalOptions* = set[TGlobalOption]

const
  harmlessOptions* = {optForceFullMake, optNoLinking, optRun,
                      optUseColors, optStdout}

type
  TCommands* = enum           # Nim's commands
                              # **keep binary compatible**
    cmdNone, cmdCompileToC, cmdCompileToCpp, cmdCompileToOC,
    cmdCompileToJS,
    cmdCompileToLLVM, cmdInterpret, cmdPretty, cmdDoc,
    cmdGenDepend, cmdDump,
    cmdCheck,                 # semantic checking for whole project
    cmdParse,                 # parse a single file (for debugging)
    cmdScan,                  # scan a single file (for debugging)
    cmdIdeTools,              # ide tools
    cmdDef,                   # def feature (find definition for IDEs)
    cmdRst2html,              # convert a reStructuredText file to HTML
    cmdRst2tex,               # convert a reStructuredText file to TeX
    cmdInteractive,           # start interactive session
    cmdRun,                   # run the project via TCC backend
    cmdJsonScript             # compile a .json build file
  TStringSeq* = seq[string]
  TGCMode* = enum             # the selected GC
    gcNone, gcBoehm, gcRegions, gcMarkAndSweep, gcDestructors,
    gcRefc, gcV2, gcGo
    # gcRefc and the GCs that follow it use a write barrier,
    # as far as usesWriteBarrier() is concerned

  IdeCmd* = enum
    ideNone, ideSug, ideCon, ideDef, ideUse, ideDus, ideChk, ideMod,
    ideHighlight, ideOutline, ideKnown, ideMsg

  Feature* = enum  ## experimental features; DO NOT RENAME THESE!
    implicitDeref,
    dotOperators,
    callOperator,
    parallel,
    destructor,
    notnil,
    dynamicBindSym,
    forLoopMacros,
    caseStmtMacros,
    codeReordering,
    compiletimeFFI,
      ## This requires building nim with `-d:nimHasLibFFI`
      ## which itself requires `nimble install libffi`, see #10150
      ## Note: this feature can't be localized with {.push.}

  SymbolFilesOption* = enum
    disabledSf, writeOnlySf, readOnlySf, v2Sf

  TSystemCC* = enum
    ccNone, ccGcc, ccNintendoSwitch, ccLLVM_Gcc, ccCLang, ccLcc, ccBcc, ccDmc, ccWcc, ccVcc,
    ccTcc, ccPcc, ccUcc, ccIcl, ccIcc, ccClangCl

  CfileFlag* {.pure.} = enum
    Cached,    ## no need to recompile this time
    External   ## file was introduced via .compile pragma

  Cfile* = object
    nimname*: string
    cname*, obj*: AbsoluteFile
    flags*: set[CfileFlag]
  CfileList* = seq[Cfile]

  Suggest* = ref object
    section*: IdeCmd
    qualifiedPath*: seq[string]
    name*: ptr string         # not used beyond sorting purposes; name is also
                              # part of 'qualifiedPath'
    filePath*: string
    line*: int                   # Starts at 1
    column*: int                 # Starts at 0
    doc*: string           # Not escaped (yet)
    forth*: string               # type
    quality*: range[0..100]   # matching quality
    isGlobal*: bool # is a global variable
    contextFits*: bool # type/non-type context matches
    symkind*: byte
    scope*, localUsages*, globalUsages*: int # more usages is better
    tokenLen*: int
    version*: int
  Suggestions* = seq[Suggest]

  ConfigRef* = ref object ## every global configuration
                          ## fields marked with '*' are subject to
                          ## the incremental compilation mechanisms
                          ## (+) means "part of the dependency"
    linesCompiled*: int  # all lines that have been compiled
    options*: TOptions    # (+)
    globalOptions*: TGlobalOptions # (+)
    macrosToExpand*: StringTableRef
    m*: MsgConfig
    evalTemplateCounter*: int
    evalMacroCounter*: int
    exitcode*: int8
    cmd*: TCommands  # the command
    selectedGC*: TGCMode       # the selected GC (+)
    verbosity*: int            # how verbose the compiler is
    numberOfProcessors*: int   # number of processors
    evalExpr*: string          # expression for idetools --eval
    lastCmdTime*: float        # when caas is enabled, we measure each command
    symbolFiles*: SymbolFilesOption

    cppDefines*: HashSet[string] # (*)
    headerFile*: string
    features*: set[Feature]
    arguments*: string ## the arguments to be passed to the program that
                       ## should be run
    ideCmd*: IdeCmd
    oldNewlines*: bool
    cCompiler*: TSystemCC
    enableNotes*: TNoteKinds
    disableNotes*: TNoteKinds
    foreignPackageNotes*: TNoteKinds
    notes*: TNoteKinds
    mainPackageNotes*: TNoteKinds
    mainPackageId*: int
    errorCounter*: int
    hintCounter*: int
    warnCounter*: int
    errorMax*: int
    configVars*: StringTableRef
    symbols*: StringTableRef ## We need to use a StringTableRef here as defined
                             ## symbols are always guaranteed to be style
                             ## insensitive. Otherwise hell would break lose.
    packageCache*: StringTableRef
    searchPaths*: seq[AbsoluteDir]
    lazyPaths*: seq[AbsoluteDir]
    outFile*: RelativeFile
    outDir*: AbsoluteDir
    prefixDir*, libpath*, nimcacheDir*: AbsoluteDir
    dllOverrides, moduleOverrides*: StringTableRef
    projectName*: string # holds a name like 'nim'
    projectPath*: AbsoluteDir # holds a path like /home/alice/projects/nim/compiler/
    projectFull*: AbsoluteFile # projectPath/projectName
    projectIsStdin*: bool # whether we're compiling from stdin
    projectMainIdx*: FileIndex # the canonical path id of the main module
    command*: string # the main command (e.g. cc, check, scan, etc)
    commandArgs*: seq[string] # any arguments after the main command
    commandLine*: string
    keepComments*: bool # whether the parser needs to keep comments
    implicitImports*: seq[string] # modules that are to be implicitly imported
    implicitIncludes*: seq[string] # modules that are to be implicitly included
    docSeeSrcUrl*: string # if empty, no seeSrc will be generated. \
    # The string uses the formatting variables `path` and `line`.

     # the used compiler
    cIncludes*: seq[AbsoluteDir]  # directories to search for included files
    cLibs*: seq[AbsoluteDir]      # directories to search for lib files
    cLinkedLibs*: seq[string]     # libraries to link

    externalToLink*: seq[string]  # files to link in addition to the file
                                  # we compiled (*)
    linkOptionsCmd*: string
    compileOptionsCmd*: seq[string]
    linkOptions*: string          # (*)
    compileOptions*: string       # (*)
    cCompilerPath*: string
    toCompile*: CfileList         # (*)
    suggestionResultHook*: proc (result: Suggest) {.closure.}
    suggestVersion*: int
    suggestMaxResults*: int
    lastLineInfo*: TLineInfo
    writelnHook*: proc (output: string) {.closure.} # cannot make this gcsafe yet because of Nimble
    structuredErrorHook*: proc (config: ConfigRef; info: TLineInfo; msg: string;
                                severity: Severity) {.closure, gcsafe.}
    cppCustomNamespace*: string

proc hcrOn*(conf: ConfigRef): bool = return optHotCodeReloading in conf.globalOptions

template depConfigFields*(fn) {.dirty.} =
  fn(target)
  fn(options)
  fn(globalOptions)
  fn(selectedGC)

const oldExperimentalFeatures* = {implicitDeref, dotOperators, callOperator, parallel}

const
  ChecksOptions* = {optObjCheck, optFieldCheck, optRangeCheck, optNilCheck,
    optOverflowCheck, optBoundsCheck, optAssert, optNaNCheck, optInfCheck,
    optStyleCheck, optRefCheck}

  DefaultOptions* = {optObjCheck, optFieldCheck, optRangeCheck,
    optBoundsCheck, optOverflowCheck, optAssert, optWarns, optRefCheck,
    optHints, optStackTrace, optLineTrace,
    optTrMacros, optNilCheck, optStyleCheck}
  DefaultGlobalOptions* = {optThreadAnalysis,
    optExcessiveStackTrace, optListFullPaths}

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

template newPackageCache*(): untyped =
  newStringTable(when FileSystemCaseSensitive:
                   modeCaseInsensitive
                 else:
                   modeCaseSensitive)

proc newConfigRef*(): ConfigRef =
  result = ConfigRef(
    selectedGC: gcRefc,
    cCompiler: ccGcc,
    verbosity: 1,
    options: DefaultOptions,
    globalOptions: DefaultGlobalOptions,
    macrosToExpand: newStringTable(modeStyleInsensitive),
    m: initMsgConfig(),
    evalExpr: "",
    cppDefines: when NimVersion < "0.20.0": initSet[string]() else: initHashSet[string](),
    headerFile: "", features: {}, foreignPackageNotes: {hintProcessing, warnUnknownMagic,
    hintQuitCalled, hintExecuting},
    notes: NotesVerbosity[1], mainPackageNotes: NotesVerbosity[1],
    configVars: newStringTable(modeStyleInsensitive),
    symbols: newStringTable(modeStyleInsensitive),
    packageCache: newPackageCache(),
    searchPaths: @[],
    lazyPaths: @[],
    outFile: RelativeFile"",
    outDir: AbsoluteDir"",
    prefixDir: AbsoluteDir"",
    libpath: AbsoluteDir"", nimcacheDir: AbsoluteDir"",
    dllOverrides: newStringTable(modeCaseInsensitive),
    moduleOverrides: newStringTable(modeStyleInsensitive),
    projectName: "", # holds a name like 'nim'
    projectPath: AbsoluteDir"", # holds a path like /home/alice/projects/nim/compiler/
    projectFull: AbsoluteFile"", # projectPath/projectName
    projectIsStdin: false, # whether we're compiling from stdin
    projectMainIdx: FileIndex(0'i32), # the canonical path id of the main module
    command: "", # the main command (e.g. cc, check, scan, etc)
    commandArgs: @[], # any arguments after the main command
    commandLine: "",
    keepComments: true, # whether the parser needs to keep comments
    implicitImports: @[], # modules that are to be implicitly imported
    implicitIncludes: @[], # modules that are to be implicitly included
    docSeeSrcUrl: "",
    cIncludes: @[],   # directories to search for included files
    cLibs: @[],       # directories to search for lib files
    cLinkedLibs: @[],  # libraries to link

    externalToLink: @[],
    linkOptionsCmd: "",
    compileOptionsCmd: @[],
    linkOptions: "",
    compileOptions: "",
    ccompilerpath: "",
    toCompile: @[],
    arguments: "",
    suggestMaxResults: 10_000
  )
  # enable colors by default on terminals
  if terminal.isatty(stderr):
    incl(result.globalOptions, optUseColors)

proc newPartialConfigRef*(): ConfigRef =
  ## create a new ConfigRef that is only good enough for error reporting.
  result = ConfigRef(
    selectedGC: gcRefc,
    verbosity: 1,
    options: DefaultOptions,
    globalOptions: DefaultGlobalOptions,
    foreignPackageNotes: {hintProcessing, warnUnknownMagic,
    hintQuitCalled, hintExecuting},
    notes: NotesVerbosity[1], mainPackageNotes: NotesVerbosity[1])

proc cppDefine*(c: ConfigRef; define: string) =
  c.cppDefines.incl define

proc importantComments*(conf: ConfigRef): bool {.inline.} = conf.cmd in {cmdDoc, cmdIdeTools}
proc usesWriteBarrier*(conf: ConfigRef): bool {.inline.} = conf.selectedGC >= gcRefc

template compilationCachePresent*(conf: ConfigRef): untyped =
  false
#  conf.symbolFiles in {v2Sf, writeOnlySf}

template optPreserveOrigSource*(conf: ConfigRef): untyped =
  optEmbedOrigSrc in conf.globalOptions

const
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

const oKeepVariableNames* = true

proc mainCommandArg*(conf: ConfigRef): string =
  ## This is intended for commands like check or parse
  ## which will work on the main project file unless
  ## explicitly given a specific file argument
  if conf.commandArgs.len > 0:
    result = conf.commandArgs[0]
  else:
    result = conf.projectName

proc existsConfigVar*(conf: ConfigRef; key: string): bool =
  result = hasKey(conf.configVars, key)

proc getConfigVar*(conf: ConfigRef; key: string, default = ""): string =
  result = conf.configVars.getOrDefault(key, default)

proc setConfigVar*(conf: ConfigRef; key, val: string) =
  conf.configVars[key] = val

proc getOutFile*(conf: ConfigRef; filename: RelativeFile, ext: string): AbsoluteFile =
  conf.outDir / changeFileExt(filename, ext)

proc absOutFile*(conf: ConfigRef): AbsoluteFile =
  conf.outDir / conf.outFile

proc prepareToWriteOutput*(conf: ConfigRef): AbsoluteFile =
  ## Create the output directory and returns a full path to the output file
  createDir conf.outDir
  return conf.outDir / conf.outFile

proc getPrefixDir*(conf: ConfigRef): AbsoluteDir =
  ## Gets the prefix dir, usually the parent directory where the binary resides.
  ##
  ## This is overridden by some tools (namely nimsuggest) via the ``conf.prefixDir``
  ## field.
  if not conf.prefixDir.isEmpty: result = conf.prefixDir
  else: result = AbsoluteDir splitPath(getAppDir()).head

proc setDefaultLibpath*(conf: ConfigRef) =
  # set default value (can be overwritten):
  if conf.libpath.isEmpty:
    # choose default libpath:
    var prefix = getPrefixDir(conf)
    when defined(posix):
      if prefix == AbsoluteDir"/usr":
        conf.libpath = AbsoluteDir"/usr/lib/nim"
      elif prefix == AbsoluteDir"/usr/local":
        conf.libpath = AbsoluteDir"/usr/local/lib/nim"
      else:
        conf.libpath = prefix / RelativeDir"lib"
    else:
      conf.libpath = prefix / RelativeDir"lib"

    # Special rule to support other tools (nimble) which import the compiler
    # modules and make use of them.
    let realNimPath = findExe("nim")
    # Find out if $nim/../../lib/system.nim exists.
    let parentNimLibPath = realNimPath.parentDir.parentDir / "lib"
    if not fileExists(conf.libpath.string / "system.nim") and
        fileExists(parentNimLibPath / "system.nim"):
      conf.libpath = AbsoluteDir parentNimLibPath

proc canonicalizePath*(conf: ConfigRef; path: AbsoluteFile): AbsoluteFile =
  result = AbsoluteFile path.string.expandFilename

proc shortenDir*(conf: ConfigRef; dir: string): string {.
    deprecated: "use 'relativeTo' instead".} =
  ## returns the interesting part of a dir
  var prefix = conf.projectPath.string & DirSep
  if startsWith(dir, prefix):
    return substr(dir, len(prefix))
  prefix = getPrefixDir(conf).string & DirSep
  if startsWith(dir, prefix):
    return substr(dir, len(prefix))
  result = dir

proc removeTrailingDirSep*(path: string): string =
  if (len(path) > 0) and (path[len(path) - 1] == DirSep):
    result = substr(path, 0, len(path) - 2)
  else:
    result = path

proc disableNimblePath*(conf: ConfigRef) =
  incl conf.globalOptions, optNoNimblePath
  conf.lazyPaths.setLen(0)

proc getOsCacheDir(): string =
  when defined(posix):
    result = getEnv("XDG_CACHE_HOME", getHomeDir() / ".cache") / "nim"
  else:
    result = getHomeDir() / genSubDir.string

proc getNimcacheDir*(conf: ConfigRef): AbsoluteDir =
  # XXX projectName should always be without a file extension!
  result = if not conf.nimcacheDir.isEmpty:
             conf.nimcacheDir
           elif conf.cmd == cmdCompileToJS:
             conf.projectPath / genSubDir
           else:
            AbsoluteDir(getOsCacheDir() / splitFile(conf.projectName).name & "_d")

proc pathSubs*(conf: ConfigRef; p, config: string): string =
  let home = removeTrailingDirSep(os.getHomeDir())
  result = unixToNativePath(p % [
    "nim", getPrefixDir(conf).string,
    "lib", conf.libpath.string,
    "home", home,
    "config", config,
    "projectname", conf.projectName,
    "projectpath", conf.projectPath.string,
    "projectdir", conf.projectPath.string,
    "nimcache", getNimcacheDir(conf).string])
  if "~/" in result:
    result = result.replace("~/", home & '/')

proc toGeneratedFile*(conf: ConfigRef; path: AbsoluteFile,
                      ext: string): AbsoluteFile =
  ## converts "/home/a/mymodule.nim", "rod" to "/home/a/nimcache/mymodule.rod"
  let (_, tail) = splitPath(path.string)
  result = getNimcacheDir(conf) / RelativeFile changeFileExt(tail, ext)

proc completeGeneratedFilePath*(conf: ConfigRef; f: AbsoluteFile,
                                createSubDir: bool = true): AbsoluteFile =
  let (_, tail) = splitPath(f.string)
  let subdir = getNimcacheDir(conf)
  if createSubDir:
    try:
      createDir(subdir.string)
    except OSError:
      writeLine(stdout, "cannot create directory: " & subdir.string)
      quit(1)
  result = subdir / RelativeFile tail
  #echo "completeGeneratedFilePath(", f, ") = ", result

proc rawFindFile(conf: ConfigRef; f: RelativeFile; suppressStdlib: bool): AbsoluteFile =
  for it in conf.searchPaths:
    if suppressStdlib and it.string.startsWith(conf.libpath.string):
      continue
    result = it / f
    if fileExists(result):
      return canonicalizePath(conf, result)
  result = AbsoluteFile""

proc rawFindFile2(conf: ConfigRef; f: RelativeFile): AbsoluteFile =
  for i, it in conf.lazyPaths:
    result = it / f
    if fileExists(result):
      # bring to front
      for j in countdown(i, 1):
        swap(conf.lazyPaths[j], conf.lazyPaths[j-1])

      return canonicalizePath(conf, result)
  result = AbsoluteFile""

proc findFile*(conf: ConfigRef; f: string; suppressStdlib = false): AbsoluteFile {.procvar.} =
  if f.isAbsolute:
    result = if f.fileExists: AbsoluteFile(f) else: AbsoluteFile""
  else:
    result = rawFindFile(conf, RelativeFile f, suppressStdlib)
    if result.isEmpty:
      result = rawFindFile(conf, RelativeFile f.toLowerAscii, suppressStdlib)
      if result.isEmpty:
        result = rawFindFile2(conf, RelativeFile f)
        if result.isEmpty:
          result = rawFindFile2(conf, RelativeFile f.toLowerAscii)

const stdlibDirs = [
  "pure", "core", "arch",
  "pure/collections",
  "pure/concurrency", "impure",
  "wrappers", "wrappers/linenoise",
  "windows", "posix", "js"]

proc findModule*(conf: ConfigRef; modulename, currentModule: string): AbsoluteFile =
  # returns path to module
  const pkgPrefix = "pkg/"
  const stdPrefix = "std/"
  var m = addFileExt(modulename, NimExt)
  if m.startsWith(pkgPrefix):
    result = findFile(conf, m.substr(pkgPrefix.len), suppressStdlib = true)
  else:
    if m.startsWith(stdPrefix):
      let stripped = m.substr(stdPrefix.len)
      for candidate in stdlibDirs:
        let path = (conf.libpath.string / candidate / stripped)
        if fileExists(path):
          m = path
          break
    let currentPath = currentModule.splitFile.dir
    result = AbsoluteFile currentPath / m
    if not fileExists(result):
      result = findFile(conf, m)

proc findProjectNimFile*(conf: ConfigRef; pkg: string): string =
  const extensions = [".nims", ".cfg", ".nimcfg", ".nimble"]
  var candidates: seq[string] = @[]
  var dir = pkg
  while true:
    for k, f in os.walkDir(dir, relative=true):
      if k == pcFile and f != "config.nims":
        let (_, name, ext) = splitFile(f)
        if ext in extensions:
          let x = changeFileExt(dir / name, ".nim")
          if fileExists(x):
            candidates.add x
    for c in candidates:
      # nim-foo foo  or  foo  nfoo
      if (pkg in c) or (c in pkg): return c
    if candidates.len >= 1:
      return candidates[0]
    dir = parentDir(dir)
    if dir == "": break
  return ""

proc canonDynlibName(s: string): string =
  let start = if s.startsWith("lib"): 3 else: 0
  let ende = strutils.find(s, {'(', ')', '.'})
  if ende >= 0:
    result = s.substr(start, ende-1)
  else:
    result = s.substr(start)

proc inclDynlibOverride*(conf: ConfigRef; lib: string) =
  conf.dllOverrides[lib.canonDynlibName] = "true"

proc isDynlibOverride*(conf: ConfigRef; lib: string): bool =
  result = optDynlibOverrideAll in conf.globalOptions or
     conf.dllOverrides.hasKey(lib.canonDynlibName)

proc parseIdeCmd*(s: string): IdeCmd =
  case s:
  of "sug": ideSug
  of "con": ideCon
  of "def": ideDef
  of "use": ideUse
  of "dus": ideDus
  of "chk": ideChk
  of "mod": ideMod
  of "highlight": ideHighlight
  of "outline": ideOutline
  of "known": ideKnown
  of "msg": ideMsg
  else: ideNone

proc `$`*(c: IdeCmd): string =
  case c:
  of ideSug: "sug"
  of ideCon: "con"
  of ideDef: "def"
  of ideUse: "use"
  of ideDus: "dus"
  of ideChk: "chk"
  of ideMod: "mod"
  of ideNone: "none"
  of ideHighlight: "highlight"
  of ideOutline: "outline"
  of ideKnown: "known"
  of ideMsg: "msg"
