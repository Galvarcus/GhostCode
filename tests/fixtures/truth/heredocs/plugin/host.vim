vim9script

# Plugin_Name: Ghostcode
# A truth family: functions that only the body of a heredoc calls, in
# code that an autocommand or execute() runs. The line above each
# declaration states whether something uses it.
# License: GNU GPL 3.0

# LIVE
def g:OnChar(ch: string)
  echo ch
enddef

# LIVE
def OnLeave()
  echo 'leave'
enddef

# GHOST
def Unused()
  echo 'unused'
enddef

# LIVE
var cmd =<< trim END
  call g:OnChar(v:char)
END

# LIVE
var leave =<< trim END
  OnLeave()
END

autocmd_add([{event: 'InsertCharPre', group: 'TruthHeredocs', cmd: cmd->join("\n")}])
execute(leave)
