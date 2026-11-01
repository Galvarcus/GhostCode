vim9script

if exists('s:is_loaded') || v:version < 901 || &cp
  finish
endif

var is_loaded: bool = true

# Plugin_Name: Ghostcode
# Defines the `:GhostCode` command, the entry point for the
# unreferenced-code analyzer implemented in autoload/ghostcode.vim.
# License: GNU GPL 3.0

import autoload 'ghostcode.vim' as G

# Whether an exported symbol is public API, so that it is never reported.
# Set it to false for a plugin whose exports only serve its own files, to
# report an export that nothing in the project uses.
g:ghostcode_exports_are_api = get(g:, 'ghostcode_exports_are_api', true)

command! -nargs=? -complete=file GhostCode G.Run(<f-args>)
