vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# dialog_popup.vim: a yes or no question in a popup, in place of confirm.
# Built on Vim's popup_dialog with its own key filter. Vim's
# popup_filter_yesno does not handle Enter, so it has no default answer.
#
# The question wraps in the popup body. Below it, a line shows the two
# answers, with the default highlighted. Keys:
#   y, Y                 Yes.
#   n, N, x, Esc, C-c    No.
#   Enter                The default answer.
# Other keys do nothing. OnYes runs only for yes.
#
# Unlike confirm, the popup does not wait for the answer: the caller puts
# the work for yes in OnYes. The popup does not change the current window,
# so OnYes runs in the window that was current when the question opened.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/wrap.vim' as WR
import autoload 'bartleby/locale/ui.vim' as MI
import 'bartleby/variables/constants.vim' as CO

const WIDTH: number = 60
const ZINDEX: number = 320
const PROP_DEFAULT: string = 'BartlebyDialogDefault'
const YES_KEYS: list<string> = ['y', 'Y']
const NO_KEYS: list<string> = ['n', 'N', 'x', "\<Esc>", "\<C-c>"]

# FUNCTION: Ask question in a popup and call OnYes when the answer is
# yes, or OnNo when it is no. defaultYes sets the answer that Enter
# gives. A caller passes OnNo when the writer should hear what was kept,
# because Enter answers the question and a writer who takes Enter for
# the step that confirms may not have meant to answer at all. A popup
# closed by anything but an answer calls neither. Return the popup id.
export def Confirm(question: string, OnYes: func(), defaultYes: bool = false,
    OnNo: func() = null_function): number
  if empty(prop_type_get(PROP_DEFAULT))
    prop_type_add(PROP_DEFAULT, {highlight: 'PmenuSel'})
  endif
  var lines: list<string> = []
  for para in split(question, "\n")
    lines += WR.Wrap(para, WIDTH)
  endfor
  # A translation keeps the y and n keys visible, such as [Y] Ja.
  var yesLabel: string = MI.Es()
  var noLabel: string = MI.Msg()
  var answers: string = $'{yesLabel}   {noLabel}'
  lines += ['', answers]

  var id: number = popup_dialog(lines, {
    title: printf(CO.TITLE_FMT, MI.Confirm()),
    zindex: ZINDEX,
    padding: [0, 1, 0, 1],
    filter: (winid, key) => Filter(winid, key, defaultYes),
    callback: (_, result) => {
      if result == 1
        OnYes()
      elseif result == 0 && OnNo != null_function
        OnNo()
      endif
    },
  })
  var start: number = defaultYes ? 1 : strlen(yesLabel) + 4
  var length: number = defaultYes ? strlen(yesLabel) : strlen(noLabel)
  prop_add(len(lines), start, {type: PROP_DEFAULT, length: length, bufnr: winbufnr(id)})
  return id
enddef

# FUNCTION: Close the popup with 1 for yes or 0 for no. Every key is
# taken, so no key reaches the buffer while the question is open.
def Filter(winid: number, key: string, defaultYes: bool): bool
  if index(YES_KEYS, key) >= 0
    popup_close(winid, 1)
  elseif index(NO_KEYS, key) >= 0
    popup_close(winid, 0)
  elseif key ==# CO.KEY_CR
    popup_close(winid, defaultYes ? 1 : 0)
  endif
  return true
enddef
