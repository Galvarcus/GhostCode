vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_focus.vim: Focus of focus.vim works in a tab of its own and
# changes options for its layout. Leaving it puts back every option it
# saved, the tabs, and the buffer. A size given while it is active changes
# the size instead of leaving, and becomes the size that Ctrl-W = goes
# back to.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/focus.vim' as F

# FUNCTION: Return the options that Focus saves when it starts.
def Options(): dict<any>
  return {laststatus: &laststatus, showtabline: &showtabline, fillchars: &fillchars,
    winminwidth: &winminwidth, winwidth: &winwidth, winminheight: &winminheight,
    winheight: &winheight, ruler: &ruler, sidescroll: &sidescroll,
    sidescrolloff: &sidescrolloff}
enddef

# FUNCTION: Start in a new buffer with text, and return its number.
def NewText(): number
  enew!
  setline(1, ['Some words to write.', 'More words.'])
  return bufnr()
enddef

def Test_leaving_puts_back_the_options_the_tabs_and_the_buffer(): void
  var buf: number = NewText()
  var before: dict<any> = Options()
  var tabs: number = tabpagenr('$')
  F.Execute(false, '')
  assert_true(exists('t:bartleby_focus_session'), 'Focus did not start')
  assert_equal(tabs + 1, tabpagenr('$'))
  assert_equal(buf, bufnr())
  F.Execute(true, '')
  assert_false(exists('t:bartleby_focus_session'), 'Focus did not end')
  assert_equal(before, Options())
  assert_equal(tabs, tabpagenr('$'))
  assert_equal(buf, bufnr())
  bwipe!
enddef

def Test_toggle_twice_changes_nothing(): void
  var buf: number = NewText()
  var before: dict<any> = Options()
  var tabs: number = tabpagenr('$')
  F.Toggle()
  F.Toggle()
  assert_equal(before, Options())
  assert_equal([tabs, buf], [tabpagenr('$'), bufnr()])
  bwipe!
enddef

def Test_a_size_while_active_changes_the_size(): void
  NewText()
  F.Execute(false, '')
  F.Execute(false, '40')
  assert_true(exists('t:bartleby_focus_session'), 'a size ended Focus')
  if exists('t:bartleby_focus_session')
    # The size asked for last is the one that Ctrl-W = goes back to.
    assert_equal('40', t:bartleby_focus_session.dimExpr)
    # An invalid size changes nothing.
    F.Execute(false, 'not a size')
    assert_equal('40', t:bartleby_focus_session.dimExpr)
    F.Execute(true, '')
  endif
  bwipe!
enddef

export def RunAll(): void
  Test_leaving_puts_back_the_options_the_tabs_and_the_buffer()
  Test_toggle_twice_changes_nothing()
  Test_a_size_while_active_changes_the_size()
enddef
