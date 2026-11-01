vim9script

##############################################################################
# Plugin_Name: Logger
# A second script that throws a Fmt exception, for the test that catches
# it in another script.
# License: GNU GPL 3.0
##############################################################################

import 'Logger/logger.vim' as Log

var log = Log.Logger.new('Test', 'thrower.vim')

# FUNCTION: Return name when it is this. Else throw.
export def GetThat(name: string): string
  if name ==# 'this'
    return name
  endif
  throw log.Fmt('dangit')
enddef
