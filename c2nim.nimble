version       = "0.9.13"
author        = "Andreas Rumpf"
description   = "c2nim is a tool to translate Ansi C code to Nim."
license       = "MIT"
skipDirs      = @["doc"]

skipExt = @["nim"]

bin = @["c2nim"]

requires "nim >= 0.18.0", "compiler#53ce58f050247"

task test, "runs c2nim tests":
  exec "nimble build"
  exec "nim c --run testsuite/tester.nim"
