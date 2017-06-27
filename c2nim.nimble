version       = "0.9.13"
author        = "Andreas Rumpf"
description   = "c2nim is a tool to translate Ansi C code to Nim."
license       = "MIT"
skipDirs      = @["doc","testsuite"]
bin = @["c2nim"]

requires "nim >= 0.16.0", "compiler >= 0.16.0"

task tests, "runs c2nim tests":
  exec "nim c c2nim.nim"
  exec "nim c --run testsuite/tester.nim"