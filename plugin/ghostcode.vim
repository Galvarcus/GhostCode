vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif

var is_loaded: bool = true

# Plugin_Name: Ghostcode
# Defines the `:GhostCode` command, the entry point for the
# unreferenced-code analyzer that autoload/ghostcode.vim runs.
# License: GNU GPL 3.0

import autoload 'ghostcode.vim' as G

# Ghostcode has two settings, and this script sets neither.
#
# g:ghostcode_exports_are_api says whether an exported symbol is public
# API, so that nothing reports it. Its default is true, and it lives in
# the binary, which is also what reads a project's ghostcode.toml. A
# default assigned here would be indistinguishable from a value the
# user chose, and would override that file for every project.
#
# g:ghostcode_bin names the binary to run, for a copy that is neither
# on $PATH nor beside this plugin.

command! -nargs=? -complete=file GhostCode G.Run(<f-args>)
