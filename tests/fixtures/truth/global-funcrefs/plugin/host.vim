vim9script

# Plugin_Name: Ghostcode
# A truth family: a global function read as a value, not called, where
# an export is no public API. The line above each declaration states
# whether something uses it.
# License: GNU GPL 3.0

# LIVE
def g:TruthFuncrefRead()
enddef

# GHOST
def g:TruthFuncrefUnread()
enddef

# LIVE
def Run()
  # LIVE
  const F = g:TruthFuncrefRead
  F()
enddef

Run()
