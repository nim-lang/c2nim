version       = "0.9.13"
author        = "Andreas Rumpf"
description   = "c2nim is a tool to translate Ansi C code to Nim."
license       = "MIT"
skipDirs      = @["doc"]

skipExt = @["nim"]

bin = @["c2nim"]

requires "nim >= 0.18.1", "compiler >= 0.18.1"

import strutils

task test, "runs c2nim tests":
  exec "nimble build"
  exec "nim c --run testsuite/tester.nim"

task docs, "build c2nim's docs":
  exec "nim rst2html --putenv:c2nimversion=$1 doc/c2nim.rst" % version
