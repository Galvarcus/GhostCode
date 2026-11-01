vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# log.vim: gives every script its Logger, named with PLUGIN_NAME from
# constants.vim, so no script writes the plugin name itself.
#
# Logger derives the names of its options from the plugin name, in
# lowercase: g:logger_bartleby_<option>. For example, to write Bartleby's
# messages to a log file under ~/.Logger:
#   g:logger_bartleby_log_file = true
# See the Logger README for every option.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as LO
import 'bartleby/variables/constants.vim' as CO


# FUNCTION: Return a Logger for script, the file name of the calling
# script. The caller passes expand('<sfile>:t'), because <sfile> expanded
# here would not name the caller.
export def New(script: string): LO.Logger
  return LO.Logger.new(CO.PLUGIN_NAME, script)
enddef
