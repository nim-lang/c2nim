# Small program that runs the test cases

import strutils, os
const
  dir = parentDir(currentSourcePath()) & "/" # "testsuite/"
  c2nim = parentDir(dir) & "/c2nim"
  c2nimCmd = c2nim & " $#"
  cpp2nimCmd = c2nim & " --cpp $#"
  hpp2nimCmd = c2nim & " --cpp --header $#"

var
  failures = 0

proc test(t, cmd: string) =
  if execShellCmd(cmd % t) != 0: quit("FAILURE")
  let nimFile = splitFile(t).name & ".nim"
  if readFile(dir & "tests" / nimFile) != readFile(dir & "results" / nimFile):
    echo "FAILURE: files differ: ", nimFile
    discard execShellCmd("diff -uNdw " & dir & "results" / nimFile & " " & dir & "tests" / nimFile)
    failures += 1
    when false:
      copyFile(dir & "tests" / nimFile, dir & "results" / nimFile)
  else:
    echo "SUCCESS: files identical: ", nimFile

for t in walkFiles(dir & "tests/*.c"): test(t, c2nimCmd)
for t in walkFiles(dir & "tests/*.h"): test(t, c2nimCmd)
for t in walkFiles(dir & "tests/*.cpp"): test(t, cpp2nimCmd)
for t in walkFiles(dir & "tests/*.hpp"): test(t, hpp2nimCmd)

if failures > 0: quit($failures & " failures occurred.")
