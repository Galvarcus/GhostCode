vim9script
##############################################################################
# Plugin_Name: Bartleby
# tests/test_binder.vim: the mapping from cursor line to row in
# binder.vim, and the cursor restore of CursorContext and Render. Both
# are local to the script, as are all key handlers, so the tests drive
# the real buffer mappings with feedkeys and the xt flags: x runs the keys
# at once, and t makes them typed, so the mappings apply. Then they check
# the buffer, cursor, and window. Needs real files on disk, as
# test_compile.vim does, because OpenUnderCursor checks filereadable.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/path.vim' as PA
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Open the Binder for a new copy of the fixture project, with
# real scene files on disk, and return a dict of project, scene1, and
# scene2. The caller must call CloseBinderAndCleanup.
def OpenBinderWithContent(): dict<any>
  var project = FI.BuildProject()
  var chapter1 = project.ChildAt(1).ChildAt(0)
  var chapter2 = project.ChildAt(1).ChildAt(1)
  var scene1 = chapter1.ChildAt(0)
  var scene2 = chapter2.ChildAt(0)
  FI.WriteDocContent(project, scene1, ['Scene one text.'])
  FI.WriteDocContent(project, scene2, ['Scene two text.'])
  B.Show(project)
  return {project: project, scene1: scene1, scene2: scene2}
enddef

def CloseBinderAndCleanup(fx: dict<any>): void
  # Close every window but one, then wipe what is left, so that the next
  # test starts with one clean window.
  only!
  bwipe!
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_show_renders_project_name_as_title_line(): void
  var fx = OpenBinderWithContent()
  assert_equal(fx.project.name, getline(1))
  CloseBinderAndCleanup(fx)
enddef

def Test_show_renders_the_tree_starting_at_line_2(): void
  var fx = OpenBinderWithContent()
  assert_match('Front Matter', getline(2))
  assert_match('Manuscript', getline(3))
  CloseBinderAndCleanup(fx)
enddef

# FUNCTION: Regression test for the header line offset: CR on a document
# must open that document, not another one or nothing, when a title line
# is above the tree.
def Test_cr_on_a_scene_line_opens_the_correct_file(): void
  var fx = OpenBinderWithContent()
  # Find the line of Scene 1 instead of assuming it, so that this test does
  # not check the wrong line if the fixture tree changes.
  var target = 'Scene 1'
  var lnum = 1
  while lnum <= line('$') && getline(lnum) !~# '\V' .. target
    lnum += 1
  endwhile
  assert_true(lnum <= line('$'), 'fixture tree has no Scene 1 line to test against')
  cursor(lnum, 1)
  feedkeys("\<CR>", 'xt')
  assert_equal('scene-01.md', expand('%:t'))
  assert_equal(PA.Canon(fx.scene1.AbsPath(fx.project.BinderRoot())), PA.Canon(expand('%:p')))
  CloseBinderAndCleanup(fx)
enddef

def Test_cr_on_the_title_line_does_nothing(): void
  var fx = OpenBinderWithContent()
  var before = getline(1, '$')
  cursor(1, 1)
  feedkeys("\<CR>", 'xt')
  # Still in the Binder buffer: no document opened and no text changed.
  assert_equal(CO.BINDER_BUF, bufname('%'))
  assert_equal(before, getline(1, '$'))
  CloseBinderAndCleanup(fx)
enddef

def Test_tab_on_the_title_line_does_nothing(): void
  var fx = OpenBinderWithContent()
  var before = getline(1, '$')
  cursor(1, 1)
  feedkeys("\<Tab>", 'xt')
  assert_equal(before, getline(1, '$'))
  CloseBinderAndCleanup(fx)
enddef

def Test_cursor_stays_on_the_same_item_after_a_collapse_rerender(): void
  var fx = OpenBinderWithContent()
  # The Manuscript line, see Test_show_renders_the_tree_starting_at_line_2.
  var manuscriptLnum = 3
  assert_match('Manuscript', getline(manuscriptLnum))
  cursor(manuscriptLnum, 1)
  # Collapse it.
  feedkeys("\<Tab>", 'xt')
  # The cursor must stay on the Manuscript row, although Render rewrote the
  # whole buffer.
  assert_match('Manuscript', getline('.'))
  assert_equal(manuscriptLnum, line('.'))
  # And collapsing had an effect: Chapter 1, on the next line before, is no
  # longer in the buffer.
  assert_equal(0, search('Chapter\|^\s*1$', 'n'))
  CloseBinderAndCleanup(fx)
enddef

# FUNCTION: Regression test for a real bug: closing the Binder saved its
# state after its window had closed, when GetCollapsedIds found no window
# and returned nothing, so every close erased the collapsed folders.
def Test_collapsed_folders_survive_closing_the_binder(): void
  var fx = OpenBinderWithContent()
  var manuscript = fx.project.ChildAt(1)
  cursor(3, 1)
  feedkeys("\<Tab>", 'xt')
  B.Toggle(fx.project)
  assert_false(B.IsOpen())
  assert_equal([manuscript.id], B.GetCollapsedIds())
  B.Toggle(fx.project)
  assert_true(B.IsOpen())
  assert_equal(0, search('Chapter\|^\s*1$', 'n'))
  CloseBinderAndCleanup(fx)
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
enddef

# FUNCTION: Return the id of item, or an empty string for null_object.
def IdOf(item: any): string
  return item is null_object ? '' : item.id
enddef

# FUNCTION: Return the id of the item on the cursor line of the Binder,
# or an empty string on the title line or below the tree.
def IdAtCursor(): string
  var idx: number = line('.') - 2
  return idx >= 0 && idx < len(b:bartleby_rows) ? b:bartleby_rows[idx].item.id : ''
enddef

# FUNCTION: J on the last scene of a chapter moves it to the top of the
# next chapter, which opens if it was collapsed, and the cursor follows.
def Test_j_moves_a_scene_into_a_collapsed_next_chapter(): void
  var fx = OpenBinderWithContent()
  var chapter1 = fx.project.ChildAt(1).ChildAt(0)
  var chapter2 = fx.project.ChildAt(1).ChildAt(1)
  var scene = chapter1.ChildAt(0)
  b:bartleby_collapsed = {[chapter2.id]: true}
  cursor(search('Scene 1', 'n'), 1)
  feedkeys('J', 'xt')
  assert_equal(scene.id, IdOf(chapter2.ChildAt(0)))
  assert_false(has_key(b:bartleby_collapsed, chapter2.id))
  assert_equal(scene.id, IdAtCursor())
  CloseBinderAndCleanup(fx)
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
enddef

# FUNCTION: m opens a picker of folders. Typing 2 leaves the second
# chapter, and Enter moves the scene to its end.
def Test_m_moves_a_scene_to_the_chosen_folder(): void
  var fx = OpenBinderWithContent()
  var chapter1 = fx.project.ChildAt(1).ChildAt(0)
  var chapter2 = fx.project.ChildAt(1).ChildAt(1)
  var scene = chapter1.ChildAt(0)
  cursor(search('Scene 1', 'n'), 1)
  # Without the mapping, m would wait for the name of a mark and stop the
  # tests, so check it first.
  if maparg('m', 'n') ==# ''
    assert_report('m is not mapped in the Binder')
  else
    feedkeys("m2\<CR>", 'xt')
  endif
  assert_equal(0, chapter1.ChildCount())
  assert_equal(2, chapter2.ChildCount())
  if chapter2.ChildCount() == 2
    assert_equal(scene.id, chapter2.ChildAt(1).id)
  endif
  assert_equal(scene.id, IdAtCursor())
  CloseBinderAndCleanup(fx)
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
enddef

# FUNCTION: Answer an open confirmation with key. With none open, report
# it instead, because y or n alone would start a Vim command that waits
# for input and stops the tests.
def Answer(key: string): void
  if empty(popup_list())
    assert_report($'no confirmation was open to answer {key}')
    return
  endif
  feedkeys(key, 'xt')
enddef

# FUNCTION: Return the id of the first item in the Trash, or an empty
# string when it is empty.
def FirstInTrash(project: any): string
  var trash = project.TrashFolder()
  return trash.ChildCount() == 0 ? '' : trash.ChildAt(0).id
enddef

# FUNCTION: dd moves a scene into the Trash without a question, and u in
# the Trash puts it back where it was.
def Test_dd_and_u_move_a_scene_to_the_trash_and_back(): void
  var fx = OpenBinderWithContent()
  var chapter1 = fx.project.ChildAt(1).ChildAt(0)
  cursor(search('Scene 1', 'n'), 1)
  feedkeys('dd', 'xt')
  assert_equal(0, chapter1.ChildCount())
  assert_equal(fx.scene1.id, FirstInTrash(fx.project))
  # The cursor stays on the scene, now in the Trash.
  assert_equal(fx.scene1.id, IdAtCursor())
  feedkeys('u', 'xt')
  assert_equal(fx.scene1.id, chapter1.ChildCount() == 0 ? '' : chapter1.ChildAt(0).id)
  assert_equal('', FirstInTrash(fx.project))
  assert_true(filereadable(fx.scene1.AbsPath(fx.project.BinderRoot())))
  CloseBinderAndCleanup(fx)
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
enddef

# FUNCTION: dd in the Trash asks first. n keeps the scene and its file, and
# y deletes them for good.
def Test_dd_in_the_trash_deletes_for_good_only_after_yes(): void
  var fx = OpenBinderWithContent()
  var path: string = fx.scene1.AbsPath(fx.project.BinderRoot())
  cursor(search('Scene 1', 'n'), 1)
  feedkeys('dd', 'xt')
  feedkeys('dd', 'xt')
  Answer('n')
  assert_equal(fx.scene1.id, FirstInTrash(fx.project))
  assert_true(filereadable(path))
  feedkeys('dd', 'xt')
  Answer('y')
  assert_equal('', FirstInTrash(fx.project))
  assert_false(filereadable(path))
  CloseBinderAndCleanup(fx)
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
enddef

# FUNCTION: dd on the Trash itself empties it, after a yes.
def Test_dd_on_the_trash_empties_it(): void
  var fx = OpenBinderWithContent()
  var paths: list<string> = [fx.scene1, fx.scene2]->mapnew((_, s) => s.AbsPath(fx.project.BinderRoot()))
  # From the top each time, so that the search finds a scene in a chapter,
  # not the one already in the Trash.
  for _ in range(2)
    cursor(1, 1)
    cursor(search('Scene 1', 'n'), 1)
    feedkeys('dd', 'xt')
  endfor
  cursor(search('Trash/', 'n'), 1)
  feedkeys('dd', 'xt')
  Answer('y')
  assert_equal('', FirstInTrash(fx.project))
  assert_equal([0, 0], paths->mapnew((_, p) => filereadable(p)))
  CloseBinderAndCleanup(fx)
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
enddef

# FUNCTION: In the Trash, J and >> change nothing. They act without a
# prompt, so a broken guard fails here instead of waiting for input.
def Test_keys_that_change_the_tree_are_refused_in_the_trash(): void
  var fx = OpenBinderWithContent()
  cursor(search('Scene 1', 'n'), 1)
  feedkeys('dd', 'xt')
  var trash = fx.project.TrashFolder()
  assert_equal(fx.scene1.id, FirstInTrash(fx.project))
  feedkeys('J', 'xt')
  feedkeys('>>', 'xt')
  assert_equal(1, trash.ChildCount())
  assert_equal(fx.scene1.id, FirstInTrash(fx.project))
  CloseBinderAndCleanup(fx)
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
enddef

# FUNCTION: u into a collapsed chapter, inside a collapsed Manuscript,
# opens both, and the cursor follows.
def Test_u_opens_the_collapsed_folder_it_restores_into(): void
  var fx = OpenBinderWithContent()
  var chapter1 = fx.project.ChildAt(1).ChildAt(0)
  cursor(search('Scene 1', 'n'), 1)
  feedkeys('dd', 'xt')
  var manuscript = fx.project.ChildAt(1)
  b:bartleby_collapsed = {[chapter1.id]: true, [manuscript.id]: true}
  feedkeys('u', 'xt')
  assert_false(has_key(b:bartleby_collapsed, chapter1.id))
  assert_false(has_key(b:bartleby_collapsed, manuscript.id))
  assert_equal(fx.scene1.id, IdAtCursor())
  CloseBinderAndCleanup(fx)
  execute 'silent! bwipe! ' .. CO.BINDER_BUF
enddef

export def RunAll(): void
  Test_show_renders_project_name_as_title_line()
  Test_show_renders_the_tree_starting_at_line_2()
  Test_cr_on_a_scene_line_opens_the_correct_file()
  Test_cr_on_the_title_line_does_nothing()
  Test_tab_on_the_title_line_does_nothing()
  Test_cursor_stays_on_the_same_item_after_a_collapse_rerender()
  Test_collapsed_folders_survive_closing_the_binder()
  Test_j_moves_a_scene_into_a_collapsed_next_chapter()
  Test_m_moves_a_scene_to_the_chosen_folder()
  Test_dd_and_u_move_a_scene_to_the_trash_and_back()
  Test_dd_in_the_trash_deletes_for_good_only_after_yes()
  Test_dd_on_the_trash_empties_it()
  Test_keys_that_change_the_tree_are_refused_in_the_trash()
  Test_u_opens_the_collapsed_folder_it_restores_into()
enddef
