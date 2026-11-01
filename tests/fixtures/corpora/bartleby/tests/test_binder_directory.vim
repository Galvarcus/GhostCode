vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_binder_directory.vim: the folder name rule of
# syntax/bartleby-binder.vim, bartlebyBinderDirectory, linked to
# Directory, checked for each byte column with synID. Also checks that the
# rule leaves the Chapter and Part prefixes, documents, and label colors
# alone. Needs :syntax on, see the header of tests/test_syntax.vim.
# License: GNU GPL 3.0
##############################################################################

def GroupAt(lnum: number, col: number): string
  return synIDattr(synID(lnum, col, 1), 'name')
enddef

def AssertGroup(expected: string, lnum: number, first: number, last: number): void
  for col in range(first, last)
    assert_equal(expected, GroupAt(lnum, col), $'line {lnum}, col {col}')
  endfor
enddef

def Test_folder_names_are_directory_and_prefixes_keep_their_group(): void
  new
  setlocal buftype=nofile
  setline(1, [
    'Project',
    '▾ Front Matter/',
    '  ▾ Chapter: 1/',
    '    · Scene 1 (Red)',
    '▸ Research/',
    '  · Notes/',
    '  ▾ Part: One/',
  ])
  setlocal filetype=bartleby-binder
  # Front Matter line: the marker is bytes 1 to 3, the name bytes 5 to 17.
  AssertGroup('bartlebyBinderMarker', 2, 1, 3)
  AssertGroup('bartlebyBinderDirectory', 2, 5, 17)
  # Chapter line: the prefix is bytes 7 to 15, the name and slash 16 to 17.
  AssertGroup('bartlebyBinderRoleLabel', 3, 7, 15)
  AssertGroup('bartlebyBinderDirectory', 3, 16, 17)
  # A document: the title is plain, and the label color has its own group.
  AssertGroup('', 4, 8, 14)
  AssertGroup('bartlebyBinderItemLabel', 4, 15, 20)
  # A collapsed folder.
  AssertGroup('bartlebyBinderDirectory', 5, 5, 13)
  # A document whose title ends in a slash is not a folder.
  AssertGroup('', 6, 6, 11)
  # The Part prefix, then the name.
  AssertGroup('bartlebyBinderRoleLabel', 7, 7, 12)
  AssertGroup('bartlebyBinderDirectory', 7, 13, 16)
  bwipe!
enddef

def Test_directory_group_links_to_directory(): void
  new
  setlocal buftype=nofile
  setline(1, ['Project', '▾ Research/'])
  setlocal filetype=bartleby-binder
  assert_equal('Directory', synIDattr(synIDtrans(synID(2, 5, 1)), 'name'))
  bwipe!
enddef

export def RunAll(): void
  syntax on
  Test_folder_names_are_directory_and_prefixes_keep_their_group()
  Test_directory_group_links_to_directory()
enddef
