vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_outliner.vim: the popup Filter of outliner.vim. OutlinerPopup
# is local to the script, unlike InputPopup, so the tests cannot build
# one. They open a real popup with the exported Show and drive it with
# feedkeys and the xt flags. This reaches a popup filter even headless:
# popup key dispatch is inside Vim, not in terminal drawing. Chained
# pickers are checked by their titles, with popup_list and
# popup_getoptions, not by reading private state.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/outliner.vim' as O
import './fixtures.vim' as FI
import autoload 'bartleby/path.vim' as PA

def OpenOutlinerWithContent(): dict<any>
  var project = FI.BuildProject()
  var manuscript = project.ChildAt(1)
  var chapter1 = manuscript.ChildAt(0)
  var scene1 = chapter1.ChildAt(0)
  var chapter2 = manuscript.ChildAt(1)
  var scene2 = chapter2.ChildAt(0)
  FI.WriteDocContent(project, scene1, ['Scene one content.'])
  FI.WriteDocContent(project, scene2, ['Scene two content.'])
  O.Show(project, manuscript)
  return {project: project, scene1: scene1, scene2: scene2}
enddef

def ClosePopupsAndCleanup(fx: dict<any>): void
  for id in popup_list()
    popup_close(id)
  endfor
  FI.CleanupProjectFiles(fx.project)
enddef

# FUNCTION: Regression test for a real bug: CR on a document row opened
# the document in the window that was current when the Outliner opened,
# which is the Binder in a new session, not an editor window, because a
# popup does not change the focus. This test uses the smallest case, with
# nothing else open, as testing_checklist.md advises for this kind of bug.
def Test_cr_opens_the_correct_document_in_a_fresh_session(): void
  var fx = OpenOutlinerWithContent()
  # Row 0 is the folder of Chapter 1, and row 1 its Scene 1.
  feedkeys("j", 'xt')
  feedkeys("\<CR>", 'xt')
  assert_equal('scene-01.md', expand('%:t'))
  assert_equal(PA.Canon(fx.scene1.AbsPath(fx.project.BinderRoot())), PA.Canon(expand('%:p')))
  bwipe!
  ClosePopupsAndCleanup(fx)
enddef

def Test_cr_on_a_folder_row_does_not_open_anything(): void
  var fx = OpenOutlinerWithContent()
  var before = expand('%:p')
  # Row 0 is the folder of Chapter 1, not a document.
  feedkeys("\<CR>", 'xt')
  assert_equal(before, expand('%:p'))
  ClosePopupsAndCleanup(fx)
enddef

def Test_j_then_j_reaches_the_second_chapters_scene(): void
  var fx = OpenOutlinerWithContent()
  # Rows: 0 Chapter 1, 1 its Scene 1, 2 Chapter 2, 3 the Scene 1 of
  # Chapter 2.
  feedkeys("jjj", 'xt')
  feedkeys("\<CR>", 'xt')
  assert_equal(PA.Canon(fx.scene2.AbsPath(fx.project.BinderRoot())), PA.Canon(expand('%:p')))
  bwipe!
  ClosePopupsAndCleanup(fx)
enddef

# FUNCTION: Regression test for a real bug: a popup filter receives one
# key at a time and does not buffer key sequences, so an early version
# ran Status, bound to s, instead of Sort for gs.
def Test_gs_opens_the_sort_popup_not_the_status_popup(): void
  var fx = OpenOutlinerWithContent()
  # Move to a document row first.
  feedkeys("j", 'xt')
  feedkeys("gs", 'xt')
  var titles = popup_list()->mapnew((_, id) => popup_getoptions(id).title)
  assert_true(index(titles, ' Sort by ') >= 0)
  assert_equal(-1, index(titles, ' Status '))
  ClosePopupsAndCleanup(fx)
enddef

def Test_bare_s_opens_the_status_popup(): void
  var fx = OpenOutlinerWithContent()
  feedkeys("j", 'xt')
  feedkeys("s", 'xt')
  var titles = popup_list()->mapnew((_, id) => popup_getoptions(id).title)
  assert_true(index(titles, ' Status ') >= 0)
  ClosePopupsAndCleanup(fx)
enddef

def Test_bare_l_opens_the_label_popup(): void
  var fx = OpenOutlinerWithContent()
  feedkeys("j", 'xt')
  feedkeys("l", 'xt')
  var titles = popup_list()->mapnew((_, id) => popup_getoptions(id).title)
  assert_true(index(titles, ' Label ') >= 0)
  ClosePopupsAndCleanup(fx)
enddef

export def RunAll(): void
  Test_cr_opens_the_correct_document_in_a_fresh_session()
  Test_cr_on_a_folder_row_does_not_open_anything()
  Test_j_then_j_reaches_the_second_chapters_scene()
  Test_gs_opens_the_sort_popup_not_the_status_popup()
  Test_bare_s_opens_the_status_popup()
  Test_bare_l_opens_the_label_popup()
enddef
