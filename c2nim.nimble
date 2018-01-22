version       = "0.9.13"
author        = "Andreas Rumpf"
description   = "c2nim is a tool to translate Ansi C code to Nim."
license       = "MIT"
skipDirs      = @["doc"]

bin = @["c2nim"]

# Actually requires nim commit 07fe1aa655dc75eec1a4cf4c697615b5642e8a7c or later
requires "nim > 0.17.2", "compiler > 0.17.2"

task tests, "runs c2nim tests":
  exec "nim c c2nim.nim"
  exec "nim c --run testsuite/tester.nim"