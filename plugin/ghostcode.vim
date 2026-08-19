vim9script

if exists('s:is_loaded')
  finish
endif
var is_loaded: bool = true

import autoload 'ghostcode.vim' as ghostcode

command! -nargs=? -complete=file GhostCode ghostcode.Run(<f-args>)
