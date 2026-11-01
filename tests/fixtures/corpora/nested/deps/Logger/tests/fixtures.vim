vim9script

##############################################################################
# Plugin_Name: Logger
# Shared setup for the tests.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/messages.vim' as M

# FUNCTION: Remove all Logger options and messages, then point the log
# folder at a new temporary path so that no test writes to ~/.Logger.
# Return that path.
export def Reset(): string
  for k in keys(g:)->filter((_, n) => n =~# '^logger_')
    execute $'unlet g:{k}'
  endfor
  var dir: string = tempname()
  g:logger_log_dir = dir
  M.Clear()
  return dir
enddef

# FUNCTION: Return the lines of the only log file in dir. Return an empty
# list when dir has no log file.
export def LogLines(dir: string): list<string>
  var files: list<string> = glob($'{dir}/*.log', true, true)
  return len(files) == 1 ? readfile(files[0]) : []
enddef
