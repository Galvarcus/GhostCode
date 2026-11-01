vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif

var is_loaded: bool = true

# Plugin_Name: Ghostcode
# Gives each Ghostcode script its Logger, named with PLUGIN_NAME, so that
# no script writes the plugin name itself. Logger derives its option
# names from the plugin name in lowercase: g:logger_ghostcode_<option>.
# License: GNU GPL 3.0

import 'Logger/logger.vim' as LO

export const PLUGIN_NAME: string = 'Ghostcode'

# METHOD: Return a Logger for script, the file name of the calling script.
# The caller passes expand('<sfile>:t'), because <sfile> expanded here
# would not name the caller.
export def New(script: string): LO.Logger
  return LO.Logger.new(PLUGIN_NAME, script)
enddef
