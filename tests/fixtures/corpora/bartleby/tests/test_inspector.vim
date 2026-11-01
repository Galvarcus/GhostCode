vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_inspector.vim: the Inspector follows the editor with a hook
# on every buffer change while it is open. Closed in any way, not only
# with Toggle, it stops: the hook removes itself. It opens again as often
# as it is closed, and shows only the document that it opens for: its
# buffer stays hidden while closed, and must take new text. Linked from
# lists the documents that link to the one shown, and opens them.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binderitem.vim' as BI
import autoload 'bartleby/inspector.vim' as I
import autoload 'bartleby/links.vim' as LK
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/trash.vim' as TR
import autoload 'bartleby/tree.vim' as T
import autoload 'bartleby/path.vim' as PA
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

def Test_the_follow_hook_goes_when_the_inspector_closes_any_way(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  FI.WriteDocContent(project, scene, ['Text.'])
  ST.Set(project)
  execute 'silent edit ' .. fnameescape(scene.AbsPath(project.BinderRoot()))
  var editor: number = win_getid()
  I.Toggle()
  assert_true(exists('#bartleby_inspector_follow#BufEnter'), 'no hook while open')
  # Closed without Toggle.
  execute ':' .. bufwinnr(CO.INSPECTOR_BUF) .. 'close'
  win_gotoid(editor)
  doautocmd BufEnter
  assert_false(exists('#bartleby_inspector_follow#BufEnter'), 'the hook stayed')
  execute 'silent! bwipe! ' .. CO.INSPECTOR_BUF
  bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Return the text of the Inspector buffer.
def InspectorText(): string
  return join(getbufline(CO.INSPECTOR_BUF, 1, '$'), "\n")
enddef

# FUNCTION: Open, close, and open the Inspector again with Toggle. The
# second opening once failed with E21.
# REFERENCE: https://github.com/Galvarcus/bartleby/issues/1
def Test_the_inspector_opens_again_after_it_closes(): void
  var project = FI.BuildProject()
  var scene = project.ChildAt(1).ChildAt(0).ChildAt(0)
  FI.WriteDocContent(project, scene, ['Text.'])
  ST.Set(project)
  execute 'silent edit ' .. fnameescape(scene.AbsPath(project.BinderRoot()))
  for step in ['open', 'close', 'open again', 'close again', 'open a third time']
    try
      I.Toggle()
    catch
      assert_report($'{step}: {v:exception}')
    endtry
  endfor
  assert_true(bufwinnr(CO.INSPECTOR_BUF) != -1, 'the Inspector is not open')
  assert_match(scene.title, InspectorText())
  I.Toggle()
  execute 'silent! bwipe! ' .. CO.INSPECTOR_BUF
  bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: Opened again for another document, the Inspector shows only
# that document, even when it has fewer lines than the first.
def Test_the_inspector_opens_again_for_another_document_without_its_old_lines(): void
  var project = FI.BuildProject()
  var first = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var second = project.ChildAt(1).ChildAt(1).ChildAt(0)
  FI.WriteDocContent(project, first, ['Text.'])
  FI.WriteDocContent(project, second, ['Text.'])
  var meta = first.LoadMeta(project.BinderRoot())
  meta.SetSynopsis(repeat('A synopsis long enough to take several lines. ', 6))
  meta.Save(first.MetaPath(project.BinderRoot()))
  ST.Set(project)
  execute 'silent edit ' .. fnameescape(first.AbsPath(project.BinderRoot()))
  I.Toggle()
  assert_match('A synopsis long enough', InspectorText())
  I.Toggle()
  execute 'silent edit ' .. fnameescape(second.AbsPath(project.BinderRoot()))
  try
    I.Toggle()
  catch
    assert_report('opening again: ' .. v:exception)
  endtry
  assert_notmatch('A synopsis long enough', InspectorText())
  silent! I.Toggle()
  execute 'silent! bwipe! ' .. CO.INSPECTOR_BUF
  silent! :%bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(project)
enddef

# FUNCTION: The fixture project with documents that link to Mara: Scene
# 1 of chapter 1 by her title, Notes without case, Mara to herself, a
# document in the Trash, and Scene 1 of chapter 2 to a missing title.
def LinkProject(): any
  var project = FI.BuildProject()
  var chars = project.ChildAt(3)
  var research = project.ChildAt(4)
  chars.AddChild(BI.BinderItem.NewDocument('Mara', 'characters/mara.md'))
  research.AddChild(BI.BinderItem.NewDocument('Notes', 'research/notes.md'))
  research.AddChild(BI.BinderItem.NewDocument('Ghost', 'research/ghost.md'))
  var text: dict<list<string>> = {
    'Scene 1 1': ['See [[Mara]].'], 'Scene 1 2': ['[[Nobody]] only.'],
    Mara: ['I am [[Mara]], see [[Scene 1]].'], Notes: ['Ask [[mara|her]].'], Ghost: ['[[Mara]]'],
  }
  FI.WriteDocContent(project, project.ChildAt(1).ChildAt(0).ChildAt(0), text['Scene 1 1'])
  FI.WriteDocContent(project, project.ChildAt(1).ChildAt(1).ChildAt(0), text['Scene 1 2'])
  for item in [chars.ChildAt(0), research.ChildAt(0), research.ChildAt(1)]
    FI.WriteDocContent(project, item, text[item.title])
  endfor
  TR.MoveToTrash(project, T.FindRowById(T.Flatten(project), research.ChildAt(1).id))
  ST.Set(project)
  return project
enddef

# FUNCTION: Open the Inspector for item and return the lines of Linked
# from, after its header.
def LinkedLines(project: any, item: any): list<string>
  execute 'silent edit ' .. fnameescape(item.AbsPath(project.BinderRoot()))
  I.Toggle()
  var lines: list<string> = getbufline(CO.INSPECTOR_BUF, 1, '$')
  var idx: number = index(lines, I.LinkedHeader())
  I.Toggle()
  if idx < 0
    return ['(no section)']
  endif
  var rest: list<string> = lines[idx + 1 :]
  var stop: number = index(rest, '')
  return stop < 0 ? rest : rest[: stop - 1]
enddef

def CloseLinks(project: any): void
  execute 'silent! bwipe! ' .. CO.INSPECTOR_BUF
  silent! :%bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(project)
enddef

def Test_linked_from_lists_the_documents_that_link_here(): void
  var project = LinkProject()
  assert_equal(['Scene 1  Manuscript / 1', 'Notes  Research'], LinkedLines(project, project.ChildAt(3).ChildAt(0)))
  CloseLinks(project)
enddef

# FUNCTION: Two documents share the title Scene 1, so a link to it counts
# for both, as gf offers both.
def Test_a_link_to_a_shared_title_counts_for_both(): void
  var project = LinkProject()
  assert_equal(['Mara  Characters'], LinkedLines(project, project.ChildAt(1).ChildAt(0).ChildAt(0)))
  assert_equal(['Mara  Characters'], LinkedLines(project, project.ChildAt(1).ChildAt(1).ChildAt(0)))
  CloseLinks(project)
enddef

# FUNCTION: The buffer stays current, because leaving it would save it.
def Test_an_unsaved_link_counts(): void
  var project = LinkProject()
  var scene2 = project.ChildAt(1).ChildAt(1).ChildAt(0)
  execute 'silent edit ' .. fnameescape(scene2.AbsPath(project.BinderRoot()))
  setline(1, 'Now [[Mara]].')
  assert_equal(['Scene 1', 'Scene 1', 'Notes'],
    LK.LinkedFrom(project, project.ChildAt(3).ChildAt(0))->mapnew((_, d) => d.title))
  assert_equal(['[[Nobody]] only.'], readfile(scene2.AbsPath(project.BinderRoot())))
  set nomodified
  CloseLinks(project)
enddef

def Test_no_links_show_a_dash_and_a_screenplay_has_no_section(): void
  var project = LinkProject()
  assert_equal(['-'], LinkedLines(project, project.ChildAt(4).ChildAt(0)))
  project.InitNew(project.name, CO.TYPE_SCREENPLAY)
  assert_equal(['(no section)'], LinkedLines(project, project.ChildAt(4).ChildAt(0)))
  CloseLinks(project)
enddef

def Test_e_and_enter_open_a_linked_document(): void
  var project = LinkProject()
  var mara = project.ChildAt(3).ChildAt(0)
  var notes = project.ChildAt(4).ChildAt(0)
  for key in ['e', "\<CR>"]
    execute 'silent edit ' .. fnameescape(mara.AbsPath(project.BinderRoot()))
    I.Toggle()
    win_gotoid(bufwinid(CO.INSPECTOR_BUF))
    cursor(index(getline(1, '$'), 'Notes  Research') + 1, 1)
    feedkeys(key, 'xt')
    assert_equal(PA.Canon(notes.AbsPath(project.BinderRoot())), PA.Canon(expand('%:p')), strtrans(key))
    I.Toggle()
  endfor
  CloseLinks(project)
enddef

# FUNCTION: A file that changes is read again, though its time may be the
# same second as before.
def Test_a_changed_file_is_read_again(): void
  var project = LinkProject()
  var mara = project.ChildAt(3).ChildAt(0)
  var scene2 = project.ChildAt(1).ChildAt(1).ChildAt(0)
  assert_equal(['Scene 1', 'Notes'], LK.LinkedFrom(project, mara)->mapnew((_, d) => d.title))
  writefile(['Later [[Mara]] came.'], scene2.AbsPath(project.BinderRoot()))
  assert_equal(['Scene 1', 'Scene 1', 'Notes'], LK.LinkedFrom(project, mara)->mapnew((_, d) => d.title))
  CloseLinks(project)
enddef

def Test_a_heading_link_counts_as_a_link(): void
  var project = LinkProject()
  var scene2 = project.ChildAt(1).ChildAt(1).ChildAt(0)
  writefile(['See [[Mara#Backstory]] there.'], scene2.AbsPath(project.BinderRoot()))
  assert_equal(['Scene 1', 'Scene 1', 'Notes'],
    LK.LinkedFrom(project, project.ChildAt(3).ChildAt(0))->mapnew((_, d) => d.title))
  CloseLinks(project)
enddef

export def RunAll(): void
  Test_the_follow_hook_goes_when_the_inspector_closes_any_way()
  Test_the_inspector_opens_again_after_it_closes()
  Test_the_inspector_opens_again_for_another_document_without_its_old_lines()
  Test_linked_from_lists_the_documents_that_link_here()
  Test_a_link_to_a_shared_title_counts_for_both()
  Test_an_unsaved_link_counts()
  Test_no_links_show_a_dash_and_a_screenplay_has_no_section()
  Test_e_and_enter_open_a_linked_document()
  Test_a_changed_file_is_read_again()
  Test_a_heading_link_counts_as_a_link()
enddef
