vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# helppopup.vim: a popup that lists the keys of a pane, shown with ?, as
# in NERDTree. Shared by the Binder, Outliner, Corkboard, scrive list,
# lookup popup, and compile selection pane. Plain text. Esc closes it,
# and it takes every other key while it is open.
# License: GNU GPL 3.0
##############################################################################

import 'bartleby/variables/constants.vim' as CO
import autoload 'bartleby/locale/views.vim' as MV
const HELP_ZINDEX: number = 300
const HELP_MINWIDTH: number = 40

# FUNCTION: Show entries, a list of key and description pairs in the
# caller's order. title is the border title, or Help when it is empty.
export def Show(title: string, entries: list<list<string>>): void
  var popupTitle: string = printf(' %s ', title ==# '' ? MV.Help() : title)

  var keyWidth: number = 0
  for entry in entries
    keyWidth = max([keyWidth, strchars(entry[0])])
  endfor

  var lines: list<string> = ['']
  for entry in entries
    lines->add(printf('  %-' .. keyWidth .. 's   %s', entry[0], entry[1]))
  endfor
  lines->add('')
  lines->add('  ' .. MV.PressEscClose())

  popup_create(lines, {
    title: popupTitle,
    border: [1, 1, 1, 1],
    padding: [0, 1, 0, 1],
    zindex: HELP_ZINDEX,
    minwidth: HELP_MINWIDTH,
    filter: (id: number, key: string): bool => {
      if key ==# CO.KEY_ESC
        popup_close(id)
      endif
      return true
    },
  })
enddef
