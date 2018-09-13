when NimMajor == 0 and NimMinor >= 18 and NimPatch >= 1:
  switch("nilseqs", "on")
else:
  switch("nilseqs", "off")