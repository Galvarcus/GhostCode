vim9script

##############################################################################
# Plugin_Name: Bartleby
# tests/test_panes.vim: the panes of Bartleby, the Binder and the Inspector,
# and the edit window. Focus, Spotlight, and Quill work only in the edit
# window, and never in a pane. When the last edit window closes and a pane
# is left, an empty edit window takes its place between the panes, and the
# panes keep their widths. The panes are made here with the names that
# Bartleby gives them, and without a scrive.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/focus.vim' as F
import autoload 'bartleby/quill.vim' as Q
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/windows.vim' as W
import 'bartleby/variables/constants.vim' as CO
import autoload 'bartleby/path.vim' as PA
import './fixtures.vim' as FI

const BINDER_WIDTH: number = 30
const INSPECTOR_WIDTH: number = 24

# FUNCTION: Open a pane named name at the side, topleft or botright, with
# width, and some lines with a blank line between, as the Inspector has.
def OpenPane(name: string, side: string, width: number): number
  execute side .. ' vnew'
  execute 'vertical resize ' .. width
  setlocal buftype=nofile bufhidden=wipe noswapfile winfixwidth
  execute 'silent file ' .. fnameescape(name)
  setline(1, ['Title: One', '', 'Label: Two', '', 'Synopsis'])
  setlocal nomodifiable
  return win_getid()
enddef

# FUNCTION: Return the window ids of a layout of the edit window with a file
# of two paragraphs, and the Binder and the Inspector when asked, and watch
# the edit window.
def Layout(binder: bool, inspector: bool): dict<any>
  silent! only
  silent! :%bwipe!
  var file: string = FI.TempPath() .. '.md'
  writefile(['One one.', '', 'Two two.'], file)
  execute 'silent edit ' .. fnameescape(file)
  # The window that :only kept may be a pane of an earlier test, and a pane
  # keeps its width, which would squeeze the panes made here.
  setlocal nowinfixwidth
  var ids: dict<any> = {file: file, edit: win_getid()}
  if binder
    ids.binder = OpenPane(CO.BINDER_BUF, 'topleft', BINDER_WIDTH)
  endif
  if inspector
    ids.inspector = OpenPane(CO.INSPECTOR_BUF, 'botright', INSPECTOR_WIDTH)
  endif
  # Opening the second pane squeezes the first, so set the widths last.
  if binder
    win_execute(ids.binder, 'vertical resize ' .. BINDER_WIDTH)
  endif
  if inspector
    win_execute(ids.inspector, 'vertical resize ' .. INSPECTOR_WIDTH)
  endif
  win_gotoid(ids.edit)
  W.WatchEditWin()
  return ids
enddef

def Close(ids: dict<any>): void
  SP.Off()
  augroup bartleby_windows
    autocmd!
  augroup END
  silent! only
  silent! :%bwipe!
  delete(ids.file)
enddef

# FUNCTION: Return the ids of the windows of the current tab that show a
# buffer that is not a pane, in order.
def EditWindows(): list<number>
  return range(1, winnr('$'))->mapnew((_, n) => win_getid(n))
    ->filter((_, id) => !W.IsChromeBuf(winbufnr(id)))
enddef

def PrepareSpotlight(): void
  highlight Normal ctermfg=252 ctermbg=235 guifg=#d0d0d0 guibg=#262626
  set t_Co=256
  # Spotlight needs a color model for its dim color, and 256 colors is the
  # one these tests set up, see Dim in spotlight.vim. A system that keeps
  # its own count sends Dim to its last branch, which throws, and then
  # every assertion below fails for a reason of its own, so the premise
  # says so itself.
  assert_equal('256', &t_Co, 'the system kept its own color count')
enddef

# FUNCTION: Return the dim matches of the current window.
def DimMatches(): list<dict<any>>
  return getmatches()->filter((_, m) => m.group ==# 'SpotlightDim')
enddef

def Test_spotlight_dims_the_edit_window_and_never_a_pane(): void
  PrepareSpotlight()
  var ids = Layout(false, true)
  SP.Execute(false, '')
  assert_true(SP.IsOn(), $'Spotlight did not start in the edit window: {FI.LastLog()}')
  cursor(1, 1)
  doautocmd CursorMoved
  assert_false(empty(DimMatches()), 'the edit window was not dimmed')
  win_gotoid(ids.inspector)
  cursor(3, 1)
  doautocmd CursorMoved
  assert_equal([], DimMatches(), 'the Inspector was dimmed')
  Close(ids)
enddef

def Test_spotlight_is_refused_in_a_pane(): void
  PrepareSpotlight()
  var ids = Layout(true, true)
  for pane in [ids.binder, ids.inspector]
    win_gotoid(pane)
    SP.Execute(false, '')
    assert_false(SP.IsOn(), 'Spotlight started in a pane')
  endfor
  Close(ids)
enddef

def Test_focus_is_refused_in_a_pane(): void
  var ids = Layout(true, true)
  for pane in [ids.binder, ids.inspector]
    win_gotoid(pane)
    F.Execute(false, '')
    assert_false(exists('t:bartleby_focus_session'), 'Focus started in a pane')
    assert_equal(1, tabpagenr('$'))
  endfor
  Close(ids)
enddef

def Test_quill_is_refused_in_a_pane(): void
  var ids = Layout(true, true)
  for pane in [ids.binder, ids.inspector]
    win_gotoid(pane)
    Q.Init('soft')
    assert_false(exists('b:bartleby_quill'), 'Quill started in a pane')
    assert_equal('', maparg('j', 'n'), 'Quill changed the keys of a pane')
  endfor
  win_gotoid(ids.edit)
  Q.Init('soft')
  assert_equal('gj', maparg('j', 'n'), 'Quill does not work in the edit window')
  Close(ids)
enddef

# FUNCTION: Return the widths of the Binder and the Inspector, or -1 for a
# pane that is not there.
def PaneWidths(): list<number>
  var found: list<number> = [-1, -1]
  for n in range(1, winnr('$'))
    var name: string = bufname(winbufnr(n))
    if name =~# CO.BINDER_BUF .. '$'
      found[0] = winwidth(n)
    elseif name =~# CO.INSPECTOR_BUF .. '$'
      found[1] = winwidth(n)
    endif
  endfor
  return found
enddef

def Test_the_edit_window_stays_empty_between_the_panes(): void
  var ids = Layout(true, true)
  var widths: list<number> = PaneWidths()
  assert_equal([BINDER_WIDTH, INSPECTOR_WIDTH], widths)
  quit
  sleep 50m
  var edit: list<number> = EditWindows()
  assert_equal(1, len(edit), 'there is no edit window')
  if empty(edit)
    Close(ids)
    return
  endif
  assert_equal(['', 1, ['']], [bufname(winbufnr(edit[0])), line('$'), getline(1, '$')])
  assert_equal(widths, PaneWidths(), 'a pane changed its width')
  # Binder, edit window, Inspector, from the left.
  assert_equal(edit[0], win_getid())
  assert_equal([1, 2, 3], [win_id2win(ids.binder), win_id2win(edit[0]), win_id2win(ids.inspector)])
  Close(ids)
enddef

def Test_the_edit_window_stays_beside_one_pane(): void
  for [binder, inspector] in [[true, false], [false, true]]
    var ids = Layout(binder, inspector)
    var widths: list<number> = PaneWidths()
    quit
    sleep 50m
    assert_equal(1, len(EditWindows()), 'there is no edit window')
    assert_equal(widths, PaneWidths())
    if len(EditWindows()) == 1
      assert_equal(binder ? [1, 2] : [2, 1],
        [win_id2win(binder ? ids.binder : ids.inspector), win_id2win(EditWindows()[0])])
    endif
    Close(ids)
  endfor
enddef

def Test_closing_the_empty_edit_window_lets_it_go(): void
  var ids = Layout(true, true)
  quit
  sleep 50m
  assert_equal(1, len(EditWindows()))
  quit
  sleep 50m
  assert_equal([], EditWindows(), 'the empty edit window came back')
  assert_equal(2, winnr('$'))
  Close(ids)
enddef

def Test_another_edit_window_means_nothing_is_added(): void
  var ids = Layout(true, true)
  vsplit
  var windows: number = winnr('$')
  quit
  sleep 50m
  assert_equal(windows - 1, winnr('$'))
  assert_equal(1, len(EditWindows()))
  assert_equal(PA.Canon(ids.file), PA.Canon(expand('%:p')))
  Close(ids)
enddef

def Test_a_modified_buffer_keeps_its_window(): void
  var ids = Layout(true, true)
  setline(1, 'Changed')
  var windows: number = winnr('$')
  silent! quit
  sleep 50m
  assert_equal(windows, winnr('$'), 'a window was added or removed')
  assert_equal(['Changed'], getline(1, 1))
  set nomodified
  Close(ids)
enddef

def Test_without_a_pane_a_closed_window_stays_closed(): void
  var ids = Layout(false, false)
  vsplit
  quit
  sleep 50m
  assert_equal(1, winnr('$'))
  Close(ids)
enddef

export def RunAll(): void
  Test_spotlight_dims_the_edit_window_and_never_a_pane()
  Test_spotlight_is_refused_in_a_pane()
  Test_focus_is_refused_in_a_pane()
  Test_quill_is_refused_in_a_pane()
  Test_the_edit_window_stays_empty_between_the_panes()
  Test_the_edit_window_stays_beside_one_pane()
  Test_closing_the_empty_edit_window_lets_it_go()
  Test_another_edit_window_means_nothing_is_added()
  Test_a_modified_buffer_keeps_its_window()
  Test_without_a_pane_a_closed_window_stays_closed()
enddef
