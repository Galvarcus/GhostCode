vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# closeall.vim: :BartlebyClose. It closes everything of Bartleby that is
# open: Focus, Spotlight, a Scrivening, the Binder, the Inspector, the
# windows and buffers of the documents of the scrive, and the scrive itself.
# What is left is one window with an empty buffer, or the windows of other
# files, when there are any.
#
# The changes of the documents are saved first. When one cannot be saved,
# the rest stays open, and a bang throws the changes away. The session
# remembers the document, the cursor, and the Binder, so that opening the
# scrive again brings them back.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/focus.vim' as F
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/progress.vim' as PG
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/spotlight.vim' as SP
import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/locale/panes.vim' as MP
import autoload 'bartleby/path.vim' as PA
import 'bartleby/variables/constants.vim' as CO

const FOCUS_SESSION: string = 'bartleby_focus_session'

var log = L.New(expand('<sfile>:t'))

# The window options that Bartleby sets in its windows, which an empty
# buffer must not inherit, because options of a window stay with the window.
const WIN_OPTIONS: list<string> = [
  'winfixwidth', 'winfixheight', 'wrap', 'linebreak', 'breakindent',
  'breakindentopt', 'number', 'relativenumber', 'foldenable',
]

# FUNCTION: Return true when path is a file of the Binder of project.
def InScrive(project: PO.Project, path: string): bool
  return project isnot null_object && path !=# ''
    && PA.Under(project.BinderRoot(), path)
enddef

# FUNCTION: Return the buffers of the documents of project, and the one of a
# Scrivening.
def ScriveBufs(project: PO.Project): list<number>
  return getbufinfo()
    ->filter((_, info) => SV.IsScrivening(info.bufnr) || InScrive(project, info.name))
    ->mapnew((_, info) => info.bufnr)
enddef

# FUNCTION: Return the tab with a Focus session, or 0.
def FocusTab(): number
  for tabNr in range(1, tabpagenr('$'))
    if gettabvar(tabNr, FOCUS_SESSION, null_object) isnot null_object
      return tabNr
    endif
  endfor
  return 0
enddef

# FUNCTION: Return true when something of Bartleby is open.
def IsAnythingOpen(project: PO.Project): bool
  return project isnot null_object || B.IsOpen() || SV.IsOpen() || FocusTab() > 0
    || SP.IsOn() || bufwinnr(CO.INSPECTOR_BUF) != -1
enddef

# FUNCTION: Write the changes of buffer bufNr, and return true when it holds
# none afterward. The write is that of the window that shows it, so that
# the options and the hooks of the buffer apply.
def Save(bufNr: number): bool
  var wins: list<number> = win_findbuf(bufNr)
  try
    if !empty(wins)
      win_execute(wins[0], 'silent update')
    else
      writefile(getbufline(bufNr, 1, '$'), fnamemodify(bufname(bufNr), ':p'))
      setbufvar(bufNr, '&modified', 0)
    endif
  catch
    return false
  endtry
  return !getbufvar(bufNr, '&modified')
enddef

# FUNCTION: Close the windows of Bartleby in the current tab. Windows of
# other files stay. When there are none, one window stays, with an empty
# buffer that has none of the window options of Bartleby.
def CloseWins(bufNrs: list<number>): void
  var panes: list<number> = []
  var docs: list<number> = []
  var others: number = 0
  for info in getwininfo()
    if info.tabnr != tabpagenr() || win_gettype(info.winid) !=# ''
      continue
    endif
    if W.IsChromeBuf(info.bufnr)
      panes->add(info.winid)
    elseif index(bufNrs, info.bufnr) >= 0
      docs->add(info.winid)
    else
      others += 1
    endif
  endfor
  # The panes go first, so that nothing keeps an edit window for them.
  var survivor: number = 0
  if others == 0
    survivor = empty(docs) ? get(panes, 0, 0) : docs[0]
  endif
  for winId in panes + docs
    if winId != survivor && win_id2win(winId) > 0
      execute ':' .. win_id2win(winId) .. 'close'
    endif
  endfor
  if survivor > 0 && win_gotoid(survivor)
    enew
    clearmatches()
    unlet! w:bartleby_spotlight_matches
    for option in WIN_OPTIONS
      execute 'setlocal ' .. option .. '<'
    endfor
  endif
enddef

# FUNCTION: Close everything of Bartleby, as :BartlebyClose does. With
# discard, throw away the changes that cannot or should not be saved.
# Returns false, and leaves the windows open, when a change cannot be saved.
export def All(discard: bool = false): bool
  var project: PO.Project = ST.Get()
  if !IsAnythingOpen(project)
    log.Info(MP.NothingOpen())
    return true
  endif

  # Remember where the writer was, for when the scrive opens again.
  if project isnot null_object
    var docWins: list<number> = ScriveBufs(project)
      ->mapnew((_, b) => win_findbuf(b))->flattennew()->filter((_, w) => win_id2tabwin(w)[0] == tabpagenr())
    if !empty(docWins) && index(docWins, win_getid()) < 0
      win_gotoid(docWins[0])
    endif
    SS.CaptureCurDoc()
    SS.CaptureBinderState(B.IsOpen(), B.GetCollapsedIds())
  endif

  # Focus and Spotlight change the screen, so they go first.
  while FocusTab() > 0
    execute 'tabnext ' .. FocusTab()
    F.Execute(true, '')
  endwhile
  if SP.IsOn()
    SP.Execute(true, '')
  endif

  # Changes to throw away are marked as saved first, because leaving a
  # buffer would let auto-save write them.
  if discard
    for bufNr in ScriveBufs(project)
      setbufvar(bufNr, '&modified', 0)
    endfor
  endif
  # A Scrivening writes its documents, and then they are buffers of their own.
  if SV.IsOpen()
    if !SV.Close()
      log.Error(MP.ScriveningCouldNot())
      return false
    endif
  endif
  var bufNrs: list<number> = ScriveBufs(project)
  if !discard
    for bufNr in bufNrs
      if getbufvar(bufNr, '&modified') && !Save(bufNr)
        log.Error(MP.CouldNotSaved(bufname(bufNr)))
        return false
      endif
    endfor
  endif

  W.StopWatchingEditWin()
  var paneBufs: list<number> = [bufnr(CO.BINDER_BUF), bufnr(CO.INSPECTOR_BUF)]->filter((_, b) => b > 0)
  CloseWins(bufNrs)
  for bufNr in bufNrs + paneBufs
    if bufexists(bufNr)
      execute 'silent! bwipe! ' .. bufNr
    endif
  endfor
  PG.Forget()
  ST.Set(null_object)
  return true
enddef
