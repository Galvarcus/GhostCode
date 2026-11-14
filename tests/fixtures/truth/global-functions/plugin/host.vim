vim9script

# Plugin_Name: Ghostcode
# A truth family: a global function, which any user or plugin can call,
# where an export is public API. The line above each declaration states
# whether something uses it.
# License: GNU GPL 3.0

# LIVE
def g:TruthGlobalApi(): number
  return Helper()
enddef

# LIVE
def Helper(): number
  return 1
enddef

# GHOST
def Unused(): number
  return 2
enddef
