# Small program that runs the test cases

import strutils, os

const
  c2nimCmd = "c2nim $#"
  cpp2nimCmd = "c2nim --cpp $#"
  dir = "testsuite/"

var
  failures = 0

proc test(t, cmd: string) =
  if execShellCmd(cmd % t) != 0: quit("FAILURE")
  let nimFile = splitFile(t).name & ".nim"
  if replace(strip(readFile(dir & "tests" / nimFile)), "\r", "") !=
     replace(strip(readFile(dir & "results" / nimFile)), "\r", ""):
    echo "FAILURE: files differ: ", nimFile
    failures += 1
  else:
    echo "SUCCESS: files identical: ", nimFile

for t in walkFiles(dir & "tests/*.c"): test(t, c2nimCmd)
for t in walkFiles(dir & "tests/*.h"): test(t, c2nimCmd)
for t in walkFiles(dir & "tests/*.cpp"): test(t, cpp2nimCmd)

if failures > 0: quit($failures & " failures occurred.")
