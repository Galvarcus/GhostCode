vim9script

##############################################################################
# Plugin_Name: Ghostcode
# tests/skip.vim: the register of tests that did not run. A test whose
# conditions the running Vim cannot meet, such as a patch it lacks or a
# platform it is not, records itself here and returns, so that the harness
# names it in tests/results.txt. A skip that is not named reads as a pass,
# and this project has twice been given a pass by a run where nothing ran.
# License: GNU GPL 3.0
##############################################################################

var skipped: list<string> = []

# FUNCTION: Record a test that did not run, under the name the harness
# reports and the reason a reader needs to judge the gap.
export def Skip(name: string, why: string): void
  add(skipped, $'{name} ({why})')
enddef

# FUNCTION: Every test that did not run, in the order they were
# recorded.
export def Skipped(): list<string>
  return skipped
enddef
