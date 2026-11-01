vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_closeall.vim: :BartlebyClose of closeall.vim. It saves the
# documents, closes Focus, Spotlight, a Scrivening, the Binder, the
# Inspector, and the documents of the scrive, forgets the scrive, and
# leaves one window with an empty buffer, or the windows of other files.
# A change that cannot be saved keeps everything open, and a bang throws
# changes away. The panes are made here with the names that Bartleby gives
# them.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/closeall.vim' as CA
import autoload 'bartleby/path.vim' as PA
import autoload 'bartleby/focus.vim' as F
import autoload 'bartleby/persist.vim' as PE
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/windows.vim' as W
import './fixtures.vim' as FI
import 'bartleby/variables/constants.vim' as CO

# FUNCTION: Return the fixture project, current, with its two scenes on
# disk.
def NewProject(): dict<any>
  var project = FI.BuildProject()
  var scene1 = project.ChildAt(1).ChildAt(0).ChildAt(0)
  var scene2 = project.ChildAt(1).ChildAt(1).ChildAt(0)
  FI.WriteDocContent(project, scene1, ['One one.'])
  FI.WriteDocContent(project, scene2, ['Two two.'])
  ST.Set(project)
  var root: string = project.BinderRoot()
  return {project: project, manuscript: project.ChildAt(1), scene1: scene1,
    path1: scene1.AbsPath(root), path2: scene2.AbsPath(root)}
enddef

def OpenPane(name: string, side: string, width: number): number
  execute side .. ' vnew'
  execute 'vertical resize ' .. width
  setlocal buftype=nofile bufhidden=hide noswapfile winfixwidth
  execute 'silent file ' .. fnameescape(name)
  setline(1, ['Pane'])
  return win_getid()
enddef

# FUNCTION: Open the first scene, and the Binder and the Inspector when
# asked, as windows named as Bartleby names them.
def Layout(fx: dict<any>, binder: bool, inspector: bool): void
  silent! only
  silent! :%bwipe!
  execute 'silent edit ' .. fnameescape(fx.path1)
  setlocal nowinfixwidth
  if binder
    OpenPane(CO.BINDER_BUF, 'topleft', 24)
  endif
  if inspector
    OpenPane(CO.INSPECTOR_BUF, 'botright', 20)
  endif
  var edit: number = win_findbuf(bufnr(fx.path1))[0]
  win_gotoid(edit)
  W.WatchEditWin()
enddef

def Cleanup(fx: dict<any>): void
  SP.Off()
  W.StopWatchingEditWin()
  silent! only
  silent! :%bwipe!
  ST.Set(null_object)
  FI.CleanupProjectFiles(fx.project)
enddef

def Test_it_leaves_one_window_with_an_empty_buffer(): void
  var fx = NewProject()
  Layout(fx, true, true)
  vsplit
  assert_true(CA.All())
  assert_equal(1, winnr('$'))
  assert_equal(['', 1, [''], 0], [bufname(), line('$'), getline(1, '$'), &modified ? 1 : 0])
  assert_equal(-1, bufnr(CO.BINDER_BUF))
  assert_equal(-1, bufnr(CO.INSPECTOR_BUF))
  assert_equal(-1, bufnr(fx.path1))
  assert_true(ST.Get() is null_object, 'the scrive is still open')
  Cleanup(fx)
enddef

def Test_the_changes_of_a_document_are_saved(): void
  var fx = NewProject()
  Layout(fx, true, false)
  setline(1, 'Changed.')
  assert_true(CA.All())
  assert_equal(['Changed.'], readfile(fx.path1))
  Cleanup(fx)
enddef

def Test_a_bang_throws_the_changes_away(): void
  var fx = NewProject()
  Layout(fx, true, false)
  setline(1, 'Changed.')
  assert_true(CA.All(true))
  assert_equal(['One one.'], readfile(fx.path1))
  assert_equal(['', 1], [bufname(), winnr('$')])
  Cleanup(fx)
enddef

def Test_a_scrivening_is_saved_and_closed(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  setline(4, 'New text.')
  assert_true(CA.All())
  assert_false(SV.IsOpen())
  assert_equal(['New text.'], readfile(fx.path2))
  assert_equal(['', 1], [bufname(), winnr('$')])
  Cleanup(fx)
enddef

# FUNCTION: A Scrivening that is not in a window is saved as a Scrivening,
# by its own write, and not as a file named after its buffer.
def Test_a_hidden_scrivening_is_saved_in_its_documents(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  setline(4, 'Hidden text.')
  var other: string = FI.TempPath() .. '.txt'
  writefile(['Other.'], other)
  # Leaving the Scrivening would let auto-save write it.
  var autosave: bool = g:bartleby_autosave
  g:bartleby_autosave = false
  execute 'hide edit ' .. fnameescape(other)
  assert_equal([], win_findbuf(bufnr(CO.SCRIVENINGS_BUF)))
  assert_true(CA.All())
  assert_equal(['Hidden text.'], readfile(fx.path2))
  assert_false(filereadable(CO.SCRIVENINGS_BUF), 'a file was written for the buffer')
  assert_false(SV.IsOpen())
  g:bartleby_autosave = autosave
  delete(other)
  Cleanup(fx)
enddef

def Test_a_change_that_cannot_be_saved_keeps_everything_open(): void
  var fx = NewProject()
  SV.Open(fx.project, fx.manuscript)
  setline(4, 'Never saved.')
  # As when a title line is damaged: the Scrivening cannot write.
  prop_remove({type: 'BartlebyScriveningTitle', id: 2, all: true}, 1, line('$'))
  assert_false(CA.All())
  assert_true(SV.IsOpen(), 'the Scrivening closed')
  assert_false(ST.Get() is null_object, 'the scrive was forgotten')
  assert_equal(['Two two.'], readfile(fx.path2))
  assert_true(CA.All(true))
  assert_false(SV.IsOpen())
  assert_equal(['Two two.'], readfile(fx.path2))
  Cleanup(fx)
enddef

def Test_focus_and_spotlight_are_left(): void
  highlight Normal ctermfg=252 ctermbg=235 guifg=#d0d0d0 guibg=#262626
  set t_Co=256
  # Spotlight needs a color model for its dim color, and 256 colors is the
  # one these tests set up, see Dim in spotlight.vim. A system that keeps
  # its own count sends Dim to its last branch, which throws, and then
  # every assertion below fails for a reason of its own, so the premise
  # says so itself.
  assert_equal('256', &t_Co, 'the system kept its own color count')
  var fx = NewProject()
  Layout(fx, false, false)
  F.Execute(false, '')
  assert_true(exists('t:bartleby_focus_session'), 'Focus did not start')
  SP.Execute(false, '')
  assert_true(SP.IsOn(), $'Spotlight did not start: {FI.LastLog()}')
  assert_true(CA.All())
  assert_equal(1, tabpagenr('$'))
  assert_false(exists('t:bartleby_focus_session'))
  assert_false(SP.IsOn())
  assert_equal(['', 1], [bufname(), winnr('$')])
  Cleanup(fx)
enddef

def Test_windows_of_other_files_stay(): void
  var fx = NewProject()
  Layout(fx, true, true)
  var other: string = FI.TempPath() .. '.txt'
  writefile(['Not Bartleby.'], other)
  execute 'botright split ' .. fnameescape(other)
  win_gotoid(win_findbuf(bufnr(fx.path1))[0])
  assert_true(CA.All())
  assert_equal(1, winnr('$'))
  assert_equal(PA.Canon(other), PA.Canon(expand('%:p')))
  assert_equal(['Not Bartleby.'], getline(1, '$'))
  assert_equal([-1, -1, -1], [bufnr(CO.BINDER_BUF), bufnr(CO.INSPECTOR_BUF), bufnr(fx.path1)])
  delete(other)
  Cleanup(fx)
enddef

def Test_the_empty_buffer_has_none_of_the_window_options_of_bartleby(): void
  var fx = NewProject()
  Layout(fx, true, false)
  setlocal nowrap winfixwidth linebreak
  matchadd('SpotlightDim', 'One')
  assert_true(CA.All())
  assert_equal([1, 0, 0, []], [&wrap ? 1 : 0, &winfixwidth ? 1 : 0, &linebreak ? 1 : 0, getmatches()])
  Cleanup(fx)
enddef

def Test_nothing_open_is_not_an_error(): void
  var file: string = FI.TempPath() .. '.txt'
  writefile(['Plain.'], file)
  silent! only
  silent! :%bwipe!
  execute 'silent edit ' .. fnameescape(file)
  ST.Set(null_object)
  assert_true(CA.All())
  assert_equal([PA.Canon(file), ['Plain.']], [PA.Canon(expand('%:p')), getline(1, '$')])
  silent! :%bwipe!
  delete(file)
enddef

def Test_the_session_remembers_the_document_and_the_binder(): void
  for binder in [true, false]
    var fx = NewProject()
    Layout(fx, binder, false)
    cursor(1, 3)
    var scriveDir: string = fx.project.scriveDir
    assert_true(CA.All())
    var saved = PE.ReadJson(scriveDir .. '/session.json')
    assert_equal([fx.scene1.relPath, 1, binder], [get(saved, 'activeDocRelPath', ''),
      get(saved, 'cursorLine', 0), get(saved, 'binderOpen', 'missing')])
    Cleanup(fx)
  endfor
enddef

export def RunAll(): void
  Test_it_leaves_one_window_with_an_empty_buffer()
  Test_the_changes_of_a_document_are_saved()
  Test_a_bang_throws_the_changes_away()
  Test_a_scrivening_is_saved_and_closed()
  Test_a_hidden_scrivening_is_saved_in_its_documents()
  Test_a_change_that_cannot_be_saved_keeps_everything_open()
  Test_focus_and_spotlight_are_left()
  Test_windows_of_other_files_stay()
  Test_the_empty_buffer_has_none_of_the_window_options_of_bartleby()
  Test_nothing_open_is_not_an_error()
  Test_the_session_remembers_the_document_and_the_binder()
enddef
