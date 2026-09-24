vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif
var is_loaded: bool = true

# Plugin_Name: Ghostcode
# Defines the `:GhostCode` command, the entry point for the
# unreferenced-code analyzer implemented in autoload/ghostcode.vim.
# License: GNU GPL 3.0

import autoload 'ghostcode.vim' as ghostcode

command! -nargs=? -complete=file GhostCode ghostcode.Run(<f-args>)
