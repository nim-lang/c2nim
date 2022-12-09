# Small program that runs the test cases

import strutils, os, parseopt

const
  dotslash = when defined(posix): "./" else: ""

  c2nimCmd = dotslash & "c2nim $#"
  cpp2nimCmd = dotslash & "c2nim --cpp $#"
  cpp2nimCmdKeepBodies = dotslash & "c2nim --cpp --keepBodies $#"
  hpp2nimCmd = dotslash & "c2nim --cpp --header $#"
  c2nimExtrasCmd = dotslash & "c2nim --stdints --strict --header --reordercomments --def:RCL_PUBLIC='__attribute__ ()' --def:RCL_WARN_UNUSED='__attribute__ ()' --def:'RCL_ALIGNAS(N)=__attribute__(align)' --render:extranewlines $#"
  dir = "testsuite/"
  usage = """
c2nim test runner
Usage: tester testnames [options]
  Runs all tests by default without any arguments given.
  If testnames are given, all othere tests will be skipped. Testnames are the
  test file names without extension.
Options:
  -h --help        Shows this help
  --overwrite      Overwrite the test results with the current results
"""

var
  failures = 0
  exitEarly = false
  infiles = newSeq[string](0)
  diffTool = "diff -uNdr"
  overwrite = false

for kind, key, val in getopt():
  case kind
  of cmdArgument:
    infiles.add key
  of cmdLongOption, cmdShortOption:
    case key.normalize
    of "help", "h":
      stdout.write(usage)
      exitEarly = true
    of "diff", "d":
      diffTool = val
    of "overwrite":
      overwrite = true
  else:
    stdout.writeLine("[Error] unknown option: " & key)

proc exec(cmd: string) =
  if execShellCmd(cmd) != 0: quit("FAILURE: " & cmd)

proc test(t, cmd, origin: string) =
  let (_, name, _) = splitFile(t)
  if infiles.len() > 0 and not (name in infiles):
    return
  exec(cmd % t)
  let nimFile = name & ".nim"
  if readFile(dir & origin / nimFile) != readFile(dir & "results" / nimFile):
    echo "FAILURE: files differ: ", nimFile
    discard execShellCmd(diffTool & " " & dir & "results" / nimFile & " " & dir & origin / nimFile)
    failures += 1
    if overwrite:
      copyFile(dir & origin / nimFile, dir & "results" / nimFile)
  else:
    echo "SUCCESS: files identical: ", nimFile

if not exitEarly:
  exec("nim c c2nim.nim")
  for t in walkFiles(dir & "tests/*.c"):
    test(t, c2nimCmd, "tests")
  for t in walkFiles(dir & "tests/*.h"):
    test(t, c2nimCmd, "tests")
  for t in walkFiles(dir & "tests/*.cpp"):
    test(t, cpp2nimCmd, "tests")
  for t in walkFiles(dir & "tests/*.hpp"):
    test(t, hpp2nimCmd, "tests")

  for t in walkFiles(dir & "cppkeepbodies/*.cpp"):
    test(t, cpp2nimCmdKeepBodies, "cppkeepbodies")
  for t in walkFiles(dir & "cextras/*.h"):
    test(t, c2nimExtrasCmd, "cextras")

  if failures > 0: quit($failures & " failures occurred.")
