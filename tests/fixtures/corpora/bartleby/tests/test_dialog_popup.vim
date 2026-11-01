vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_dialog_popup.vim: Confirm of dialog_popup.vim. Opens the real
# popup and answers it with feedkeys and the xt flags, which reach a popup
# filter also headless. Checks each answer key, the default for Enter in
# both directions, that OnYes runs only for yes, and that other keys leave
# the question open.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/dialog_popup.vim' as DP

# FUNCTION: Ask with Confirm, press key, and return whether OnYes ran and
# whether the popup is still open.
def Answer(key: string, defaultYes: bool = false): dict<bool>
  var result: dict<bool> = {yes: false, no: false}
  var id = DP.Confirm('Delete it?', () => {
    extend(result, {yes: true})
  }, defaultYes, () => {
    extend(result, {no: true})
  })
  feedkeys(key, 'xt')
  # Before the close below, which answers the question itself: a popup
  # closed with no result reports no, so a teardown would answer for a
  # key that left the question open.
  var out: dict<bool> = {yes: result.yes, no: result.no}
  out.open = !empty(popup_getpos(id))
  if out.open
    popup_close(id)
  endif
  return out
enddef

def Test_yes_keys_run_on_yes(): void
  for key in ['y', 'Y']
    assert_equal({yes: true, no: false, open: false}, Answer(key), key)
  endfor
enddef

def Test_no_keys_do_not_run_on_yes(): void
  for key in ['n', 'N', 'x', "\<Esc>"]
    assert_equal({yes: false, no: true, open: false}, Answer(key), key)
  endfor
enddef

def Test_enter_gives_the_default(): void
  assert_equal({yes: false, no: true, open: false}, Answer("\<CR>"))
  assert_equal({yes: true, no: false, open: false}, Answer("\<CR>", true))
enddef

def Test_other_keys_leave_the_question_open(): void
  assert_equal({yes: false, no: false, open: true}, Answer('j'))
enddef

def Test_default_answer_is_highlighted(): void
  var id = DP.Confirm('Open it?', () => {
  }, true)
  var buf = winbufnr(id)
  var last = getbufline(buf, '$')[0]
  var props = prop_list(len(getbufline(buf, 1, '$')), {bufnr: buf})
  assert_equal(1, len(props))
  assert_equal('[Y]es', strpart(last, props[0].col - 1, props[0].length))
  popup_close(id)
enddef

export def RunAll(): void
  Test_yes_keys_run_on_yes()
  Test_no_keys_do_not_run_on_yes()
  Test_enter_gives_the_default()
  Test_other_keys_leave_the_question_open()
  Test_default_answer_is_highlighted()
enddef
