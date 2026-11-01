vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# wrap.vim: wraps a string to a display width, a word at a time, and
# returns the lines. It knows nothing of cards or UI.
# License: GNU GPL 3.0
##############################################################################

export def Wrap(text: string, width: number): list<string>
  if text ==# ''
    return []
  endif

  var words: list<string> = split(text)
  var lines: list<string> = []
  var current: string = ''
  for word in words
    var candidate: string = current ==# '' ? word : current .. ' ' .. word
    if strdisplaywidth(candidate) > width && current !=# ''
      lines->add(current)
      current = word
    else
      current = candidate
    endif
  endfor
  if current !=# ''
    lines->add(current)
  endif
  return lines
enddef
