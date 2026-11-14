vim9script

# Plugin_Name: Ghostcode
# A truth family: a runner in tests/, whose top-level code a test runner
# sources. The line above each declaration states whether something
# uses it.
# License: GNU GPL 3.0

# LIVE
def Helper(): number
  return 1
enddef

# GHOST
def Unused(): number
  return 2
enddef

echomsg Helper()
