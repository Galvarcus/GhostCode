vim9script

# Plugin_Name: Ghostcode
# A truth family: legacy functions in a Vim9 file. A legacy function
# is no symbol, so one that nothing calls is a limit and not a finding.
# The line above each declaration states whether something uses it.
# License: GNU GPL 3.0

# MISSED
function Dead()
  return 2
endfunction

function Used()
  return s:Helper()
endfunction

# LIVE
def Helper(): number
  return 1
enddef

# LIVE
export def Run(): void
  echo Used()
enddef
