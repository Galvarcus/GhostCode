vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_syntax.vim: checks of the three bartleby syntax files with
# synID, column by column. Separate from the real Binder, Inspector, and
# compile pane, which test_binder.vim and others cover: a scratch buffer
# gets text in the exact format, its filetype is set directly, and the
# syntax group of each relevant column is checked. Looking at the screen
# missed two real bugs here, see testing_checklist.md, so these tests
# always check synID, never only that something is highlighted.
#
# Needs :syntax on, which works in any normal Vim install.
# License: GNU GPL 3.0
##############################################################################

def GroupAt(lnum: number, col: number): string
  return synIDattr(synID(lnum, col, 1), 'name')
enddef

def Test_binder_title_line_is_fully_highlighted(): void
  new
  setlocal buftype=nofile
  setline(1, ['My Project'])
  setlocal filetype=bartleby-binder
  for col in range(1, 10)
    assert_equal('bartlebyBinderTitle', GroupAt(1, col))
  endfor
  bwipe!
enddef

def Test_binder_marker_and_role_label_are_isolated(): void
  new
  setlocal buftype=nofile
  # The Chapter line: an indent of 2, a marker of 3 bytes, a space, the
  # Chapter prefix, then the folder name 1 with the slash of binder.vim.
  setline(1, ['Title'])
  setline(2, ['  ▾ Chapter: 1/'])
  setlocal filetype=bartleby-binder
  # Columns 3 to 5 are the 3 UTF-8 bytes of the marker.
  assert_equal('bartlebyBinderMarker', GroupAt(2, 3))
  assert_equal('bartlebyBinderMarker', GroupAt(2, 4))
  assert_equal('bartlebyBinderMarker', GroupAt(2, 5))
  # Column 6 is the plain space between the marker and the prefix.
  assert_equal('', GroupAt(2, 6))
  # Columns 7 to 15 are the Chapter prefix, 9 characters.
  for col in range(7, 15)
    assert_equal('bartlebyBinderRoleLabel', GroupAt(2, col))
  endfor
  # Columns 16 and 17 are the folder name and its slash: Directory, not
  # the prefix.
  assert_equal('bartlebyBinderDirectory', GroupAt(2, 16))
  assert_equal('bartlebyBinderDirectory', GroupAt(2, 17))
  bwipe!
enddef

def Test_binder_item_label_suffix_is_isolated_to_known_colors(): void
  new
  setlocal buftype=nofile
  setline(1, ['Title'])
  setline(2, ['  · Scene 1 (Red)'])
  setlocal filetype=bartleby-binder
  # The title Scene 1, columns 6 to 12, is plain text.
  for col in range(6, 12)
    assert_equal('', GroupAt(2, col))
  endfor
  # The label color, columns 13 to 18.
  for col in range(13, 18)
    assert_equal('bartlebyBinderItemLabel', GroupAt(2, col))
  endfor
  bwipe!
enddef

def Test_binder_does_not_highlight_an_unknown_color_name(): void
  # A title that ends in a word in parentheses that is not a real label
  # name must never match: exactly the user text that the file must not
  # highlight.
  new
  setlocal buftype=nofile
  setline(1, ['Title'])
  setline(2, ['  · My Draft (Something)'])
  setlocal filetype=bartleby-binder
  for col in range(6, 24)
    assert_equal('', GroupAt(2, col))
  endfor
  bwipe!
enddef

# FUNCTION: Open a compile pane buffer with rows. The first two lines are
# the Compile header and the project title, see RedrawSelect in
# compile.vim, so rows start on line 3.
def CompileSelectBuffer(rows: list<string>): void
  new
  setlocal buftype=nofile
  setline(1, ['*** Compile ***', 'My Project'] + rows)
  setlocal filetype=bartleby-compile-select
enddef

def Test_compile_select_header_and_title(): void
  CompileSelectBuffer(['    [x] · Scene 1'])
  for col in range(1, 15)
    assert_equal('bartlebyCompileSelectHeader', GroupAt(1, col))
  endfor
  for col in range(1, 10)
    assert_equal('bartlebyCompileSelectTitle', GroupAt(2, col))
  endfor
  bwipe!
enddef

def Test_compile_select_checkbox_and_marker_are_isolated(): void
  CompileSelectBuffer(['    [x] · Scene 1'])
  # Columns 5 to 7 are the checkbox.
  for col in range(5, 7)
    assert_equal('bartlebyCompileSelectChecked', GroupAt(3, col))
  endfor
  # Columns 9 and 10 are the 2 UTF-8 bytes of the marker.
  assert_equal('bartlebyCompileSelectMarker', GroupAt(3, 9))
  assert_equal('bartlebyCompileSelectMarker', GroupAt(3, 10))
  # The title Scene 1 must not be highlighted.
  for col in range(12, 18)
    assert_equal('', GroupAt(3, col))
  endfor
  bwipe!
enddef

def Test_compile_select_unchecked_box_is_its_own_group(): void
  CompileSelectBuffer(['  [ ] · Dedication'])
  for col in range(3, 5)
    assert_equal('bartlebyCompileSelectUnchecked', GroupAt(3, col))
  endfor
  bwipe!
enddef

def Test_compile_select_folder_name_is_directory(): void
  # The Front Matter row: 4 spaces, the marker in columns 5 to 7, a space,
  # then the name and slash in columns 9 to 21. A document title that ends
  # in a slash is not a folder.
  CompileSelectBuffer(['    ▸ Front Matter/', '  [x] · Notes/'])
  assert_equal('bartlebyCompileSelectMarker', GroupAt(3, 5))
  for col in range(9, 21)
    assert_equal('bartlebyCompileSelectDirectory', GroupAt(3, col))
  endfor
  for col in range(9, 14)
    assert_equal('', GroupAt(4, col))
  endfor
  bwipe!
enddef

def Test_inspector_header_and_field_labels_are_isolated(): void
  new
  setlocal buftype=nofile
  setline(1, ['::Inspector::'])
  setline(2, ['Title: Scene 1'])
  setline(3, ['Label: Red'])
  setline(4, ['Target: -'])
  setline(5, ['Synopsis:'])
  setlocal filetype=bartleby-inspector
  for col in range(1, 13)
    assert_equal('bartlebyInspectorHeader', GroupAt(1, col))
  endfor
  # The Title label, 7 characters, is a field label. The value after it is
  # not.
  for col in range(1, 7)
    assert_equal('bartlebyInspectorField', GroupAt(2, col))
  endfor
  for col in range(8, 14)
    assert_equal('', GroupAt(2, col))
  endfor
  # The Label label, 7 characters, the same way, on its own line.
  for col in range(1, 7)
    assert_equal('bartlebyInspectorField', GroupAt(3, col))
  endfor
  # The Target label, 8 characters.
  for col in range(1, 8)
    assert_equal('bartlebyInspectorField', GroupAt(4, col))
  endfor
  # The placeholder for an empty value is not highlighted.
  assert_equal('', GroupAt(4, 9))
  # The Synopsis header, 9 characters: the whole line, with no value on it.
  for col in range(1, 9)
    assert_equal('bartlebyInspectorSynopsisHeader', GroupAt(5, col))
  endfor
  bwipe!
enddef

export def RunAll(): void
  syntax on
  Test_binder_title_line_is_fully_highlighted()
  Test_binder_marker_and_role_label_are_isolated()
  Test_binder_item_label_suffix_is_isolated_to_known_colors()
  Test_binder_does_not_highlight_an_unknown_color_name()
  Test_compile_select_header_and_title()
  Test_compile_select_checkbox_and_marker_are_isolated()
  Test_compile_select_unchecked_box_is_its_own_group()
  Test_compile_select_folder_name_is_directory()
  Test_inspector_header_and_field_labels_are_isolated()
enddef
