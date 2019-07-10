# Small program that runs the test cases

import strutils, os, parseopt

const
  c2nimCmd = "c2nim $#"
  cpp2nimCmd = "c2nim --cpp $#"
  hpp2nimCmd = "c2nim --cpp --header $#"
  dir = "testsuite/"
  usage = """
c2nim test runner
Usage: tester testnames [options]
  Runs all tests by default without any arguments given.
  If testnames are given, all othere tests will be skipped. Testnames are the 
  test file names without extension.
Options:
  -h --help        Shows this help
"""

var
  failures = 0
  exit_early = false
  infiles = newSeq[string](0)
  diff_tool = "diff -uNdr"

for kind, key, val in getopt():
  case kind
  of cmdArgument:
    infiles.add key
  of cmdLongOption, cmdShortOption:
    case key.normalize
    of "help", "h":
      stdout.write(usage)
      exit_early = true
    of "diff", "d":
      diff_tool = val
  else:
    stdout.writeLine("[Error] unknown option: " & key)

proc test(t, cmd: string) =
  let (_, name, _) = splitFile(t)
  if infiles.len() > 0 and not (name in infiles):
    return
  if execShellCmd(cmd % t) != 0: quit("FAILURE")
  let nimFile = name & ".nim"
  if readFile(dir & "tests" / nimFile) != readFile(dir & "results" / nimFile):
    echo "FAILURE: files differ: ", nimFile
    discard execShellCmd(diff_tool & " " & dir & "results" / nimFile & " " & dir & "tests" / nimFile)
    failures += 1
    when false:
      copyFile(dir & "tests" / nimFile, dir & "results" / nimFile)
  else:
    echo "SUCCESS: files identical: ", nimFile

if not exit_early:
  for t in walkFiles(dir & "tests/*.c"): 
    test(t, c2nimCmd)
  for t in walkFiles(dir & "tests/*.h"): 
    test(t, c2nimCmd)
  for t in walkFiles(dir & "tests/*.cpp"): 
    test(t, cpp2nimCmd)
  for t in walkFiles(dir & "tests/*.hpp"): 
    test(t, hpp2nimCmd)

  if failures > 0: quit($failures & " failures occurred.")
