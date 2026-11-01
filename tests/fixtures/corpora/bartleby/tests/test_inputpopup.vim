vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_inputpopup.vim: the key handling of InputPopup, for the
# multiline and filter fields, the completion of a text field against
# real files, and the width rules. InputPopup is
# exported, so the tests call its methods directly instead of using
# feedkeys. Open must run first, so that bufnr and winid exist for Filter
# to draw into, although no real key reaches the popup.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/inputpopup.vim' as IP
import autoload 'bartleby/path.vim' as PA
import './fixtures.vim' as FI

def NewMultilinePopup(default: string): IP.InputPopup
  var fields: list<list<dict<any>>> = [[{name: 'text', type: 'multiline', rows: 5}]]
  var popup = IP.InputPopup.new(fields, {text: default}, {title: ' Test ', buttons: []})
  popup.Open()
  return popup
enddef

def Test_enter_inserts_a_newline_rather_than_submitting(): void
  var popup = NewMultilinePopup('First line')
  var submitted = false
  popup.OnSubmit((values: dict<any>) => {
    submitted = true
  })
  popup.Filter(popup.winid, "\<CR>")
  # Still open: Enter must not submit.
  assert_false(submitted)
  assert_equal("First line\n", popup.Vals().text)
  popup.Close()
enddef

def Test_typed_text_is_inserted_at_the_cursor(): void
  var popup = NewMultilinePopup('')
  for c in 'Hi'
    popup.Filter(popup.winid, c)
  endfor
  assert_equal('Hi', popup.Vals().text)
  popup.Close()
enddef

def Test_backspace_at_line_start_merges_with_previous_line(): void
  var popup = NewMultilinePopup("First\nSecond")
  # The cursor starts at the end of the first line. Move to the start of
  # the second line before the backspace.
  popup.Filter(popup.winid, "\<Down>")
  popup.Filter(popup.winid, "\<Home>")
  popup.Filter(popup.winid, "\<BS>")
  assert_equal('FirstSecond', popup.Vals().text)
  popup.Close()
enddef

def Test_ctrl_s_submits_with_the_current_text(): void
  var popup = NewMultilinePopup('Draft text')
  var received = ''
  popup.OnSubmit((values: dict<any>) => {
    received = values.text
  })
  popup.Filter(popup.winid, "\<C-s>")
  assert_equal('Draft text', received)
enddef

def Test_esc_cancels_without_calling_on_submit(): void
  var popup = NewMultilinePopup('Draft text')
  var submitted = false
  popup.OnSubmit((values: dict<any>) => {
    submitted = true
  })
  popup.Filter(popup.winid, "\<Esc>")
  assert_false(submitted)
enddef

const FILTER_OPTIONS: list<string> = ['one', 'two', 'three', 'four', 'five', 'six']

# FUNCTION: Return an open filter list with 6 options and 3 visible rows.
def NewFilterPopup(title: string = 'Pick', minWidth: number = 0): IP.InputPopup
  var fields: list<list<dict<any>>> = [[{name: 'choice', type: 'filter',
    options: FILTER_OPTIONS, maxVisible: 3}]]
  var popup = IP.InputPopup.new(fields, {}, {title: $' {title} ', buttons: [], min_width: minWidth})
  popup.Open()
  return popup
enddef

# FUNCTION: Return the option text of each visible row, without padding
# or scrollbar.
def VisibleRows(popup: IP.InputPopup): list<string>
  return getbufline(winbufnr(popup.winid), 2, 4)->mapnew((_, l) => trim(l))
enddef

def Test_filter_list_scrolls_with_the_selection(): void
  var popup = NewFilterPopup()
  assert_equal(['one', 'two', 'three'], VisibleRows(popup))
  for i in range(4)
    popup.Filter(popup.winid, "\<Down>")
  endfor
  # The fifth option is selected and visible.
  assert_equal(['three', 'four', 'five'], VisibleRows(popup))
  assert_equal('five', popup.Vals().choice)
  popup.Filter(popup.winid, "\<PageUp>")
  assert_equal(['two', 'three', 'four'], VisibleRows(popup))
  assert_equal('two', popup.Vals().choice)
  popup.Close()
enddef

def Test_filter_scrollbar_only_when_the_list_scrolls(): void
  var popup = NewFilterPopup()
  var buf = winbufnr(popup.winid)
  var bar = range(2, 4)->mapnew((_, l) => prop_list(l, {bufnr: buf, types: ['InputPopupScrollbar', 'InputPopupThumb']})->len())
  assert_equal([1, 1, 1], bar)
  # Typing makes the list shorter than its visible rows: no scrollbar.
  for c in 'fi'
    popup.Filter(popup.winid, c)
  endfor
  bar = range(2, 4)->mapnew((_, l) => prop_list(l, {bufnr: buf, types: ['InputPopupScrollbar', 'InputPopupThumb']})->len())
  assert_equal([0, 0, 0], bar)
  popup.Close()
enddef

def Test_popup_is_wide_enough_for_its_title(): void
  var title = 'A title much longer than any option'
  var popup = NewFilterPopup(title)
  assert_true(popup_getoptions(popup.winid).minwidth >= strdisplaywidth(title) + 2)
  popup.Close()
  popup = NewFilterPopup('Pick', 40)
  assert_equal(40, popup_getoptions(popup.winid).minwidth)
  popup.Close()
enddef

# FUNCTION: A text field with a maximum length stops taking characters
# there, and keeps a longer starting value whole.
def Test_text_field_stops_at_its_maximum_length(): void
  var fields: list<list<dict<any>>> = [[{name: 'zip', type: 'text'}, {name: 'state', type: 'text'}]]
  var popup = IP.InputPopup.new(fields, {state: 'Ontario'}, {maxlengths: {zip: 5, state: 3}})
  popup.Open()
  for c in '1234567'
    popup.Filter(popup.winid, c)
  endfor
  assert_equal('12345', popup.Vals().zip)
  assert_equal('Ontario', popup.Vals().state)
  popup.Close()
  # A full field still shows all of its text: the field has a column
  # for the cursor after the last character.
  popup = IP.InputPopup.new([[{name: 'cc', type: 'text'}]], {}, {widths: {cc: 2}, maxlengths: {cc: 2}})
  popup.Open()
  popup.Filter(popup.winid, 'U')
  popup.Filter(popup.winid, 'S')
  assert_match('US', getbufline(winbufnr(popup.winid), 1)[0])
  popup.Close()
enddef

# FUNCTION: Return an open popup with two text fields, and the text abcd
# in the first.
def NewTextPopup(): IP.InputPopup
  var popup = IP.InputPopup.new([[{name: 'first', type: 'text'}], [{name: 'second', type: 'text'}]],
    {first: 'abcd'}, {})
  popup.Open()
  return popup
enddef

# FUNCTION: Send each key of keys to popup, in order.
def Keys(popup: IP.InputPopup, keys: list<string>): void
  for key in keys
    popup.Filter(popup.winid, key)
  endfor
enddef

def Test_text_keys_edit_at_the_cursor(): void
  var popup = NewTextPopup()
  Keys(popup, ["\<Home>", 'X'])
  assert_equal('Xabcd', popup.Vals().first)
  Keys(popup, ["\<End>", "\<BS>"])
  assert_equal('Xabc', popup.Vals().first)
  Keys(popup, ["\<Left>", "\<Left>", "\<Del>"])
  assert_equal('Xac', popup.Vals().first)
  Keys(popup, ["\<Right>", 'Z', "\<C-a>", 'Y', "\<C-e>", 'W'])
  assert_equal('YXacZW', popup.Vals().first)
  Keys(popup, ["\<C-h>"])
  assert_equal('YXacZ', popup.Vals().first)
  Keys(popup, ["\<C-u>"])
  assert_equal('', popup.Vals().first)
  popup.Close()
enddef

def Test_tab_and_shift_tab_move_between_controls(): void
  var popup = NewTextPopup()
  assert_equal(0, popup.currentIdx)
  Keys(popup, ["\<Tab>"])
  assert_equal(1, popup.currentIdx)
  Keys(popup, ["\<C-n>", "\<C-n>", "\<C-n>"])
  assert_equal(0, popup.currentIdx)
  Keys(popup, ["\<S-Tab>"])
  assert_equal(popup.TotalControls() - 1, popup.currentIdx)
  Keys(popup, ["\<C-p>"])
  assert_equal(popup.TotalControls() - 2, popup.currentIdx)
  popup.Close()
enddef

def Test_enter_moves_on_to_the_next_field_then_the_submit_button(): void
  var popup = NewTextPopup()
  Keys(popup, ["\<CR>"])
  assert_equal(1, popup.currentIdx)
  Keys(popup, ["\<CR>"])
  assert_equal(2, popup.currentIdx)
  popup.Close()
enddef

def Test_arrows_on_buttons_stay_among_the_buttons(): void
  var popup = NewTextPopup()
  Keys(popup, ["\<Tab>", "\<Tab>"])
  assert_equal(2, popup.currentIdx)
  Keys(popup, ["\<Left>"])
  assert_equal(2, popup.currentIdx)
  Keys(popup, ["\<Right>", "\<Right>", "\<Right>"])
  assert_equal(popup.TotalControls() - 1, popup.currentIdx)
  # Typing on a button changes no field.
  Keys(popup, ['x'])
  assert_equal(['abcd', ''], [popup.Vals().first, popup.Vals().second])
  popup.Close()
enddef

def Test_arrows_choose_an_option_and_stop_at_the_ends(): void
  var popup = IP.InputPopup.new([[{name: 'kind', type: 'choice', options: ['A', 'B', 'C']}],
    [{name: 'other', type: 'text'}]], {}, {})
  popup.Open()
  Keys(popup, ["\<Right>", "\<Right>", "\<Right>"])
  assert_equal('C', popup.Vals().kind)
  Keys(popup, ["\<Left>"])
  assert_equal('B', popup.Vals().kind)
  Keys(popup, ['x', "\<Left>", "\<Left>"])
  assert_equal('A', popup.Vals().kind)
  Keys(popup, ["\<CR>"])
  assert_equal(1, popup.currentIdx)
  popup.Close()
enddef

def Test_esc_and_ctrl_s_close_the_popup(): void
  for key in ["\<Esc>", "\<C-c>", "\<C-s>"]
    var popup = NewTextPopup()
    var id: number = popup.winid
    Keys(popup, [key])
    assert_equal({}, popup_getpos(id), strtrans(key))
  endfor
enddef

def Test_enter_submits_a_popup_of_one_field(): void
  var popup = IP.InputPopup.new([[{name: 'only', type: 'text'}]], {}, {})
  popup.Open()
  var id: number = popup.winid
  Keys(popup, ['a', "\<CR>"])
  assert_equal({}, popup_getpos(id))
enddef

# FUNCTION: The layout of a form: two fields share a row, a choice takes
# a line of its own, and the buttons come last. The lines and highlights
# are those that the drawing gave before it was split into parts.
def Test_a_form_lays_out_its_rows_choices_and_buttons(): void
  var popup = IP.InputPopup.new([[{name: 'a', type: 'text'}, {name: 'b', type: 'text'}],
    [{name: 'kind', type: 'choice', options: ['One', 'Two', 'Three']}], [{name: 'c', type: 'text'}]],
    {a: 'alpha', b: 'beta', c: 'gamma'}, {})
  popup.Open()
  var buf: number = winbufnr(popup.winid)
  assert_equal(['a: alpha                 b: beta                  ',
    'kind: [ One ]  [ Two ]  [ Three ]', 'c: gamma                 ', '[ Submit ]  [ Cancel ]'],
    getbufline(buf, 1, '$'))
  assert_equal([[1, 1, 3, 'InputPopupLabel'], [1, 9, 1, 'InputPopupCursor'], [1, 26, 3, 'InputPopupLabel']],
    prop_list(1, {bufnr: buf})->mapnew((_, p) => [1, p.col, p.length, p.type]))
  popup.Close()
enddef

# FUNCTION: Return where the cursor highlight of the open popup is, as
# line and column, and whether it is on a character of its line. The
# cursor is drawn as a highlighted character, so off the end of a line it
# does not show. Empty when there is none.
def CursorShown(): list<any>
  var id: number = popup_list()[0]
  var buf: number = winbufnr(id)
  var lines: list<string> = getbufline(buf, 1, '$')
  for lnum in range(1, len(lines))
    for p in prop_list(lnum, {bufnr: buf, types: ['InputPopupCursor']})
      return [lnum, p.col, p.col <= strlen(lines[lnum - 1])]
    endfor
  endfor
  return []
enddef

# FUNCTION: The cursor shows at the end of the text, where it opens and
# where typing puts it, in an empty text, and in each kind of popup. In a
# multiline or filter popup it did not.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/3
def Test_the_cursor_shows_at_the_end_of_the_text(): void
  var saved: list<string> = []
  IP.PromptMultiline('Synopsis', "Hello\nworld", (text) => {
    saved->add(text)
  })
  assert_equal([1, 6, true], CursorShown(), 'multiline, on open')
  feedkeys("\<C-s>", 'xt')
  # The space is only drawn: the text has none.
  assert_equal(["Hello\nworld"], saved)
  IP.PromptMultiline('Synopsis', '', (text) => {
  })
  assert_equal([1, 1, true], CursorShown(), 'multiline, empty')
  feedkeys('ab', 'xt')
  assert_equal([1, 3, true], CursorShown(), 'multiline, after typing')
  popup_clear(true)
  IP.PromptFilter('Pick', ['one', 'two'], (choice) => {
  })
  assert_equal([1, 3, true], CursorShown(), 'filter, empty')
  feedkeys('o', 'xt')
  assert_equal([1, 4, true], CursorShown(), 'filter, after typing')
  popup_clear(true)
  IP.PromptText('Title', 'Scene', (text) => {
  })
  assert_equal(true, get(CursorShown(), 2, false), 'text field')
  popup_clear(true)
enddef

# FUNCTION: Return the label of the button that has focus in the open
# popup, or an empty string when the text has it.
def ActiveButton(): string
  var id: number = popup_list()[0]
  var buf: number = winbufnr(id)
  var lines: list<string> = getbufline(buf, 1, '$')
  for lnum in range(1, len(lines))
    for p in prop_list(lnum, {bufnr: buf, types: ['InputPopupButtonActive']})
      return trim(lines[lnum - 1][p.col - 1 : p.col + p.length - 2], '[] ')
    endfor
  endfor
  return ''
enddef

# FUNCTION: A synopsis saves with its Save button too, so that it saves
# where the terminal takes Ctrl-S for flow control.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/2
def Test_the_synopsis_saves_with_its_button(): void
  var saved: list<string> = []
  IP.PromptMultiline('Synopsis', 'Hello', (text) => {
    saved->add(text)
  })
  var buf: number = winbufnr(popup_list()[0])
  assert_equal('[ Save ]  [ Cancel ]', getbufline(buf, '$')[0])
  feedkeys("\<Left>\<Tab>", 'xt')
  assert_equal('Save', ActiveButton())
  assert_equal([], CursorShown(), 'the text cursor shows while a button has focus')
  # Back to the text, which takes keys again, at the cursor it had.
  feedkeys("\<S-Tab>!", 'xt')
  assert_equal('', ActiveButton())
  feedkeys("\<Tab>\<CR>", 'xt')
  assert_equal(['Hell!o'], saved)
  assert_equal([], popup_list())
enddef

def Test_the_cancel_button_of_a_synopsis_saves_nothing(): void
  var saved: list<string> = []
  IP.PromptMultiline('Synopsis', 'Hello', (text) => {
    saved->add(text)
  })
  feedkeys("\<Tab>\<Right>", 'xt')
  assert_equal('Cancel', ActiveButton())
  feedkeys("\<CR>", 'xt')
  assert_equal([], saved)
  assert_equal([], popup_list())
enddef

# The folder that the completion tests complete against, made once.
var complete_dir: string = ''

# FUNCTION: Return that folder: two files whose names share a start, a
# subfolder with one file, and a name with a space, which completion must
# return unescaped.
def CompleteDir(): string
  if complete_dir ==# ''
    complete_dir = FI.TempPath() .. '/paths'
    mkdir(complete_dir .. '/sub', 'p')
    for name in ['alpha.md', 'alto.md', 'sub/inner.md', 'with space.md']
      writefile(['Text.'], $'{complete_dir}/{name}')
    endfor
  endif
  return complete_dir
enddef

# FUNCTION: Return an open popup of one path field that completes files,
# filled with start.
def NewPathPopup(start: string): IP.InputPopup
  var popup = IP.InputPopup.new([[{name: 'path', type: 'text'}]],
    {path: start}, {complete: {path: 'file'}, widths: {path: 60}})
  popup.Open()
  return popup
enddef

def Test_tab_completes_a_path_and_cycles_through_the_matches(): void
  var dir: string = CompleteDir()
  var popup = NewPathPopup($'{dir}/al')
  Keys(popup, ["\<Tab>"])
  assert_equal(PA.Canon($'{dir}/alpha.md'), PA.Canon(popup.Vals().path))
  Keys(popup, ["\<Tab>"])
  assert_equal(PA.Canon($'{dir}/alto.md'), PA.Canon(popup.Vals().path))
  # The cycle wraps, and Shift-Tab goes back.
  Keys(popup, ["\<Tab>"])
  assert_equal(PA.Canon($'{dir}/alpha.md'), PA.Canon(popup.Vals().path))
  Keys(popup, ["\<S-Tab>"])
  assert_equal(PA.Canon($'{dir}/alto.md'), PA.Canon(popup.Vals().path))
  popup.Close()
enddef

def Test_shift_tab_completes_the_last_match_first(): void
  var dir: string = CompleteDir()
  var popup = NewPathPopup($'{dir}/al')
  Keys(popup, ["\<S-Tab>"])
  assert_equal(PA.Canon($'{dir}/alto.md'), PA.Canon(popup.Vals().path))
  popup.Close()
enddef

def Test_a_changed_text_finds_the_matches_again(): void
  var dir: string = CompleteDir()
  var popup = NewPathPopup($'{dir}/al')
  Keys(popup, ["\<Tab>", "\<BS>"])
  assert_equal(PA.Canon($'{dir}/alpha.m'), PA.Canon(popup.Vals().path))
  Keys(popup, ["\<Tab>"])
  assert_equal(PA.Canon($'{dir}/alpha.md'), PA.Canon(popup.Vals().path))
  popup.Close()
enddef

def Test_tab_after_a_completed_folder_offers_what_is_in_it(): void
  var dir: string = CompleteDir()
  var popup = NewPathPopup($'{dir}/s')
  Keys(popup, ["\<Tab>"])
  assert_equal(PA.Canon($'{dir}/sub/'), PA.Canon(popup.Vals().path))
  Keys(popup, ["\<Tab>"])
  assert_equal(PA.Canon($'{dir}/sub/inner.md'), PA.Canon(popup.Vals().path))
  popup.Close()
enddef

def Test_a_completed_name_with_a_space_is_not_escaped(): void
  var dir: string = CompleteDir()
  var popup = NewPathPopup($'{dir}/with')
  Keys(popup, ["\<Tab>"])
  assert_equal(PA.Canon($'{dir}/with space.md'), PA.Canon(popup.Vals().path))
  popup.Close()
enddef

def Test_a_path_that_matches_nothing_stays_as_it_is(): void
  var dir: string = CompleteDir()
  var popup = NewPathPopup($'{dir}/zz')
  Keys(popup, ["\<Tab>"])
  assert_equal(PA.Canon($'{dir}/zz'), PA.Canon(popup.Vals().path))
  assert_equal(0, popup.currentIdx)
  popup.Close()
enddef

def Test_tab_moves_on_from_an_empty_field_that_completes(): void
  var popup = NewPathPopup('')
  Keys(popup, ["\<Tab>"])
  assert_equal(1, popup.currentIdx)
  popup.Close()
enddef

def Test_the_cursor_follows_a_long_completed_path(): void
  var dir: string = CompleteDir()
  var popup = NewPathPopup($'{dir}/al')
  Keys(popup, ["\<Tab>"])
  var f: dict<any> = popup.fields[0]
  assert_equal(strchars(f.value), f.cursor)
  popup.Close()
enddef

export def RunAll(): void
  Test_enter_inserts_a_newline_rather_than_submitting()
  Test_typed_text_is_inserted_at_the_cursor()
  Test_backspace_at_line_start_merges_with_previous_line()
  Test_ctrl_s_submits_with_the_current_text()
  Test_esc_cancels_without_calling_on_submit()
  Test_filter_list_scrolls_with_the_selection()
  Test_filter_scrollbar_only_when_the_list_scrolls()
  Test_popup_is_wide_enough_for_its_title()
  Test_text_field_stops_at_its_maximum_length()
  Test_text_keys_edit_at_the_cursor()
  Test_tab_and_shift_tab_move_between_controls()
  Test_enter_moves_on_to_the_next_field_then_the_submit_button()
  Test_arrows_on_buttons_stay_among_the_buttons()
  Test_arrows_choose_an_option_and_stop_at_the_ends()
  Test_esc_and_ctrl_s_close_the_popup()
  Test_enter_submits_a_popup_of_one_field()
  Test_a_form_lays_out_its_rows_choices_and_buttons()
  Test_the_cursor_shows_at_the_end_of_the_text()
  Test_the_synopsis_saves_with_its_button()
  Test_the_cancel_button_of_a_synopsis_saves_nothing()
  Test_tab_completes_a_path_and_cycles_through_the_matches()
  Test_shift_tab_completes_the_last_match_first()
  Test_a_changed_text_finds_the_matches_again()
  Test_tab_after_a_completed_folder_offers_what_is_in_it()
  Test_a_completed_name_with_a_space_is_not_escaped()
  Test_a_path_that_matches_nothing_stays_as_it_is()
  Test_tab_moves_on_from_an_empty_field_that_completes()
  Test_the_cursor_follows_a_long_completed_path()
  # The completion tests share one folder of sources, so it goes once
  # they have all run.
  delete(fnamemodify(CompleteDir(), ':h'), 'rf')
enddef
