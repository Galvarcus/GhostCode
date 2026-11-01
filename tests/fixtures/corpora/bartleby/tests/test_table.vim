vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_table.vim: pipe tables. Reading and lining up a table, making
# one and changing its shape through the form, formatting when you leave
# insert mode, and keeping Quill from joining or breaking its rows.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/pos.vim' as POS
import autoload 'bartleby/quill.vim' as Q
import autoload 'bartleby/table.vim' as TB

const TOOLS: string = fnamemodify(expand('<script>'), ':p:h:h') .. '/tools'

def Scratch(lines: list<string>, filetype: string = 'markdown'): void
  enew!
  setlocal buftype=nofile
  execute 'setlocal filetype=' .. filetype
  setline(1, lines)
enddef

def Cleanup(): void
  popup_clear()
  silent! :%bwipe!
enddef

def Test_cells_split_on_bars_that_are_not_escaped(): void
  assert_equal(['a', 'b\|c', 'd'], TB.Cells('| a | b\|c | d |'))
  assert_equal(['a'], TB.Cells('  | a |'))
  assert_equal([''], TB.Cells('|  |'))
enddef

def Test_format_lines_up_columns_by_their_alignment(): void
  assert_equal(['| Name | Age |', '| :--- | --: |', '| Mara |  34 |', '| Ada  |   9 |'],
    TB.Format(['| Name | Age |', '|:--|--:|', '| Mara | 34 |', '| Ada | 9 |']))
enddef

def Test_format_centers_and_counts_display_width(): void
  assert_equal(['|  é  | 中文 |', '| :-: | ---- |', '|  x  | y    |'],
    TB.Format(['| é | 中文 |', '|:-:|---|', '| x | y |']))
enddef

def Test_format_keeps_escaped_bars_and_fills_short_rows(): void
  assert_equal(['| a\|b | c   | d   |', '| ---- | --- | --- |', '| x    |     |     |'],
    TB.Format(['| a\|b | c | d |', '|---|---|', '| x |']))
enddef

def Test_a_table_needs_its_separator_row(): void
  Scratch(['Text.', '', '| A | B |', '|---|---|', '| 1 | 2 |', '', '| not | a table |', '| just | bars |'])
  assert_equal([3, 5], TB.Bounds(4))
  assert_equal([0, 0], TB.Bounds(8))
  assert_equal([0, 0], TB.Bounds(1))
  Cleanup()
enddef

def Test_build_makes_a_header_rows_alignment_and_caption(): void
  assert_equal(['| Column 1 | Column 2 |', '| -------: | -------: |', '|          |          |', '', 'Table: Crew'],
    TB.Build(2, 1, true, 'right', 'Crew'))
  assert_equal(['|     |     |', '| :-- | :-- |', '|     |     |'], TB.Build(2, 1, false, 'left', ''))
enddef

def Test_reshape_keeps_the_text_and_counts_what_it_drops(): void
  var lines: list<string> = ['| A | B |', '|---|---|', '| 1 | 2 |', '| 3 | 4 |']
  var [grown, lost] = TB.Reshape(lines, 3, 3, true, 'keep')
  assert_equal(0, lost)
  assert_equal(['A', 'B', 'Column 3'], TB.Cells(grown[0]))
  assert_equal(['1', '2', ''], TB.Cells(grown[2]))
  assert_equal(['', '', ''], TB.Cells(grown[4]))
  var [_, dropped] = TB.Reshape(lines, 1, 1, true, 'keep')
  assert_equal(4, dropped)
enddef

def Test_turning_the_header_off_moves_its_text_down(): void
  var [out, lost] = TB.Reshape(['| A | B |', '|---|---|', '| 1 | 2 |'], 2, 2, false, 'keep')
  assert_equal(0, lost)
  assert_equal(['', ''], TB.Cells(out[0]))
  assert_equal(['A', 'B'], TB.Cells(out[2]))
  assert_equal(['1', '2'], TB.Cells(out[3]))
enddef

def Test_the_form_inserts_a_table_below_the_cursor(): void
  Scratch(['Text.'])
  TB.Submit(0, 0, {cols: '2', rows: '1', header: 'Yes', align: 'Left', caption: ''})
  assert_equal(['Text.', '', '| Column 1 | Column 2 |', '| :------- | :------- |', '|          |          |'],
    getline(1, '$'))
  assert_equal([5, 3], [line('.'), col('.')])
  Cleanup()
enddef

def Test_the_form_reshapes_a_table_and_its_caption(): void
  Scratch(['| A | B |', '|---|---|', '| 1 | 2 |', '', 'Table: Old', '', 'After.'])
  TB.Submit(1, 3, {cols: '2', rows: '2', header: 'Yes', align: 'Right', caption: 'New'})
  assert_equal(['|   A |   B |', '| --: | --: |', '|   1 |   2 |', '|     |     |', '', 'Table: New', '', 'After.'],
    getline(1, '$'))
  Cleanup()
enddef

def Test_the_form_refuses_a_bad_shape(): void
  Scratch(['Text.'])
  TB.Submit(0, 0, {cols: '0', rows: '1', header: 'Yes', align: 'Left', caption: ''})
  assert_equal(['Text.'], getline(1, '$'))
  Cleanup()
enddef

def Test_dropping_cells_with_text_asks_first(): void
  Scratch(['| A | B |', '|---|---|', '| 1 | 2 |'])
  var before: number = len(popup_list())
  TB.Submit(1, 3, {cols: '1', rows: '1', header: 'Yes', align: 'Left', caption: ''})
  assert_equal(before + 1, len(popup_list()))
  assert_equal(['| A | B |', '|---|---|', '| 1 | 2 |'], getline(1, '$'))
  Cleanup()
enddef

def Test_a_screenplay_has_no_tables(): void
  Scratch(['INT. ROOM - DAY'], 'fountain')
  var before: number = len(popup_list())
  TB.Edit()
  assert_equal(before, len(popup_list()))
  Cleanup()
enddef

def Test_the_form_opens_in_a_document(): void
  Scratch(['Text.'])
  var before: number = len(popup_list())
  TB.Edit()
  assert_equal(before + 1, len(popup_list()))
  Cleanup()
enddef

def Test_formatting_keeps_the_cursor_in_its_cell(): void
  Scratch(['| A | Bee |', '|---|---|', '| long cell | x |'])
  cursor(3, stridx(getline(3), 'x') + 1)
  TB.FormatAt(3)
  assert_equal('x', getline(3)[col('.') - 1])
  Cleanup()
enddef

def Test_leaving_insert_mode_lines_up_the_table(): void
  Scratch(['| A | Bee |', '|---|---|', '| long cell | x |'])
  cursor(3, 1)
  g:bartleby_table_autoformat = false
  doautocmd InsertLeave
  assert_equal('| A | Bee |', getline(1))
  g:bartleby_table_autoformat = true
  doautocmd InsertLeave
  assert_equal('| A         | Bee |', getline(1))
  Cleanup()
enddef

# FUNCTION: With Quill's formatexpr, wrapping at textwidth does not break a
# long row, and gq lines up the table instead of joining its rows.
def Test_quill_wrapping_leaves_a_table_whole(): void
  Scratch(['| A | B |', '|---|---|', '| 1 | 2 |'])
  setlocal formatexpr=bartleby#table#FormatExpr()
  setlocal textwidth=12 formatoptions+=t
  cursor(3, 1)
  # Without the hook on leaving insert mode, so that only typing acts.
  g:bartleby_table_autoformat = false
  normal! A more words that pass the width
  g:bartleby_table_autoformat = true
  assert_equal(3, line('$'))
  # Typing does not line up the table: that waits for leaving insert mode.
  assert_equal('| A | B |', getline(1))
  # Leaving insert mode lined up the table with the new cell. Start again.
  setline(1, ['| A | B |', '|---|---|', '| 1 | 2 |'])
  normal! gggqG
  assert_equal(['| A   | B   |', '| --- | --- |', '| 1   | 2   |'], getline(1, '$'))
  Cleanup()
enddef

def Test_quill_sets_the_table_formatexpr(): void
  Scratch(['Text.'])
  Q.Init('hard')
  assert_equal('bartleby#table#FormatExpr()', &l:formatexpr)
  Q.Init('off')
  assert_equal('', &l:formatexpr)
  Cleanup()
enddef

def Test_spotlight_skips_table_rows(): void
  assert_false(POS.IsProseLine('| a | b |', 'markdown'))
  assert_true(POS.IsProseLine('She met Mara.', 'markdown'))
enddef

def Test_the_table_key_maps_to_its_plug_name(): void
  assert_equal('<Plug>(BartlebyTable)', maparg('<leader>b<Bar>', 'n'))
enddef

def Test_both_latex_templates_load_the_table_packages(): void
  for name in ['book', 'manuscript']
    var text: string = join(readfile($'{TOOLS}/latex/{name}.tex'), "\n")
    assert_match('\$if(tables)\$\n\\usepackage{longtable,booktabs,array}', text, name)
  endfor
  assert_match('\\captionsetup{', join(readfile($'{TOOLS}/latex/manuscript.tex'), "\n"))
enddef

# FUNCTION: Pandoc 3.8.2.1 and later need the counter none for a table
# without a caption, and only their own template defines it.
def Test_both_latex_templates_define_the_none_counter(): void
  for name in ['book', 'manuscript']
    assert_match('\\newcounter{none}', join(readfile($'{TOOLS}/latex/{name}.tex'), "\n"), name)
  endfor
enddef

# FUNCTION: The bug: in a Bartleby document, Quill turns autoformat on, and
# autoformat joined a table into one line at the first key. Autoformat does
# not use formatexpr, so Quill must keep it off in a table.
def Test_quill_autoformat_leaves_a_table_whole(): void
  for above in [['Text above.', ''], ['Text right above.']]
    Scratch(above + ['| A | B |', '| --- | --- |', '| 1 | 2 |', '| 3 | 4 |', '', 'Text below.'])
    setlocal textwidth=72
    Q.Init('hard')
    Q.SetAutoFmt(1)
    var lines: number = line('$')
    cursor(len(above) + 3, 3)
    normal! ix
    assert_equal(lines, line('$'), string(above))
    Q.Init('off')
    Cleanup()
  endfor
enddef

def Test_typing_into_a_table_turns_autoformat_off(): void
  Scratch(['Text.', '', '| A | B |', '| --- | --- |', '| 1 | 2 |'])
  Q.Init('hard')
  Q.SetAutoFmt(1)
  set formatoptions+=a
  cursor(5, 3)
  doautocmd CursorMovedI
  assert_notmatch('a', &formatoptions)
  Q.Init('off')
  Cleanup()
enddef

# FUNCTION: The bug: tables lined up only in Markdown buffers, not in a new
# buffer with no filetype or a .txt file. A screenplay has no tables.
def Test_tables_line_up_in_any_buffer_but_a_screenplay(): void
  for ft in ['', 'text', 'markdown', 'fountain']
    Scratch(['| A | Bee |', '|---|---|', '| long cell | x |'], ft)
    cursor(3, 1)
    doautocmd InsertLeave
    var want: string = ft ==# 'fountain' ? '| A | Bee |' : '| A         | Bee |'
    assert_equal(want, getline(1), $'filetype "{ft}"')
    Cleanup()
  endfor
enddef

def Test_has_table_needs_a_row_and_a_separator(): void
  assert_true(TB.HasTable(['Text.', '', '| A | B |', '| --- | --- |', '| 1 | 2 |']))
  assert_false(TB.HasTable(['| just | bars |', '| no | separator |']))
  assert_false(TB.HasTable(['Text.']))
  assert_false(TB.HasTable([]))
enddef

export def RunAll(): void
  Test_cells_split_on_bars_that_are_not_escaped()
  Test_format_lines_up_columns_by_their_alignment()
  Test_format_centers_and_counts_display_width()
  Test_format_keeps_escaped_bars_and_fills_short_rows()
  Test_a_table_needs_its_separator_row()
  Test_build_makes_a_header_rows_alignment_and_caption()
  Test_reshape_keeps_the_text_and_counts_what_it_drops()
  Test_turning_the_header_off_moves_its_text_down()
  Test_the_form_inserts_a_table_below_the_cursor()
  Test_the_form_reshapes_a_table_and_its_caption()
  Test_the_form_refuses_a_bad_shape()
  Test_dropping_cells_with_text_asks_first()
  Test_a_screenplay_has_no_tables()
  Test_the_form_opens_in_a_document()
  Test_formatting_keeps_the_cursor_in_its_cell()
  Test_leaving_insert_mode_lines_up_the_table()
  Test_quill_wrapping_leaves_a_table_whole()
  Test_quill_sets_the_table_formatexpr()
  Test_spotlight_skips_table_rows()
  Test_the_table_key_maps_to_its_plug_name()
  Test_both_latex_templates_load_the_table_packages()
  Test_both_latex_templates_define_the_none_counter()
  Test_quill_autoformat_leaves_a_table_whole()
  Test_typing_into_a_table_turns_autoformat_off()
  Test_tables_line_up_in_any_buffer_but_a_screenplay()
  Test_has_table_needs_a_row_and_a_separator()
enddef
