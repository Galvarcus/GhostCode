vim9script
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/locale/panes.vim' as MP
import 'bartleby/variables/constants.vim' as CO

const PAT_NOMAGIC: string = '\V'

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# windows.vim: finds Bartleby's own pane windows, the Binder and the
# Inspector, by buffer name, so that code that opens documents always
# finds the editor window. :wincmd p is not enough: it remembers only the
# last window, which can be the Inspector instead of the editor.
# The Outliner is a popup, see outliner.vim, so it takes no window.
#
# Only the edit window takes part in Focus, Spotlight, and Quill. They call
# RefusedInPane, so that a pane keeps its keys and its text. When the edit
# window closes and a pane is left, an empty edit window takes its place,
# and the panes keep their widths.
# License: GNU GPL 3.0
##############################################################################

var log = L.New(expand('<sfile>:t'))

const CHROME_BUF_NAMES: list<string> = [
  CO.BINDER_BUF,
  CO.INSPECTOR_BUF,
]

# Side panes that code opening documents must never replace.
const PROTECTED_BUF_NAMES: list<string> = [
  CO.BINDER_BUF,
  CO.INSPECTOR_BUF,
]

def MatchesAny(bufNr: number, names: list<string>): bool
  var name: string = bufname(bufNr)
  for bufName in names
    if name =~# PAT_NOMAGIC .. bufName .. '\$'
      return true
    endif
  endfor
  return false
enddef

export def IsChromeBuf(bufNr: number): bool
  return MatchesAny(bufNr, CHROME_BUF_NAMES)
enddef

def IsProtectedBuf(bufNr: number): bool
  return MatchesAny(bufNr, PROTECTED_BUF_NAMES)
enddef

# FUNCTION: Go to the first window of the current tab that is not a
# protected pane, the Binder or the Inspector, and create one when every
# window is protected. Always succeeds, and always leaves a window that
# can be replaced.
export def GoToEditorWin(): bool
  for winNr in range(1, winnr('$'))
    if !IsProtectedBuf(winbufnr(winNr))
      execute ':' .. winNr .. 'wincmd w'
      return true
    endif
  endfor
  execute 'rightbelow vnew'
  return true
enddef

# FUNCTION: Return true when the current buffer is a pane of Bartleby, the
# Binder or the Inspector, and then say that feature works only in the edit
# window. Focus, Spotlight, and Quill call it first, because in a pane they
# would change keys, text, or the view that the pane depends on.
export def RefusedInPane(feature: string): bool
  if !IsChromeBuf(bufnr())
    return false
  endif
  log.Info(MP.WorksOnlyEdit(feature))
  return true
enddef

##############################################################################
# SECTION: The edit window. When it closes and a pane is left, an empty edit
# window takes its place, and the panes keep their widths.
##############################################################################

# FUNCTION: Return true when winId is a window for text: a normal window of
# a file or a Scrivening, not a pane, help, or a list of results.
def IsEditWin(winId: number): bool
  if win_gettype(winId) !=# ''
    return false
  endif
  var bufNr: number = winbufnr(winId)
  return bufNr > 0 && !IsChromeBuf(bufNr)
    && index(['', 'acwrite'], getbufvar(bufNr, '&buftype')) >= 0
enddef

# FUNCTION: Return true when bufNr is the empty buffer that the edit window
# shows after its document closed. Closing that window is allowed, so that
# :q goes on to end the session.
def IsPlaceholder(bufNr: number): bool
  return bufname(bufNr) ==# '' && !getbufvar(bufNr, '&modified')
    && getbufvar(bufNr, '&buftype') ==# '' && getbufline(bufNr, 1, 2) == ['']
enddef

# FUNCTION: Start keeping the edit window. See KeepEditWin.
export def WatchEditWin(): void
  augroup bartleby_windows
    autocmd!
    autocmd WinClosed * KeepEditWin()
  augroup END
enddef

# FUNCTION: Stop keeping the edit window, as when Bartleby closes.
export def StopWatchingEditWin(): void
  augroup bartleby_windows
    autocmd!
  augroup END
enddef

# FUNCTION: On WinClosed: when an edit window closes that shows a document,
# note the panes of its tab and their widths, and once the window is gone,
# make a new edit window if none is left.
def KeepEditWin(): void
  var closing: number = str2nr(expand('<amatch>'))
  if !IsEditWin(closing) || IsPlaceholder(winbufnr(closing))
    return
  endif
  var tabNr: number = win_id2tabwin(closing)[0]
  var panes: list<dict<any>> = []
  for info in getwininfo()
    if info.tabnr == tabNr && IsChromeBuf(info.bufnr)
      panes->add({winid: info.winid, name: bufname(info.bufnr), width: info.width})
    endif
  endfor
  if !empty(panes)
    # A window cannot be added while one closes. RestoreEditWin looks
    # again, because another edit window may be there by then.
    timer_start(0, (_) => RestoreEditWin(panes))
  endif
enddef

# FUNCTION: Open an empty edit window between the panes, or beside the one
# pane that is left, and give each pane the width that it had. Does nothing
# when the panes are gone, or when an edit window is there again.
def RestoreEditWin(panes: list<dict<any>>): void
  var alive: list<dict<any>> = panes->copy()->filter((_, p) => win_id2win(p.winid) > 0)
  if empty(alive)
    return
  endif
  for winNr in range(1, winnr('$'))
    if IsEditWin(win_getid(winNr))
      return
    endif
  endfor
  var binders: list<dict<any>> = alive->copy()->filter((_, p) => p.name =~# '\V' .. CO.BINDER_BUF .. '\$')
  if !empty(binders)
    win_gotoid(binders[0].winid)
    rightbelow vnew
  else
    win_gotoid(alive[0].winid)
    leftabove vnew
  endif
  for pane in alive
    win_execute(pane.winid, 'vertical resize ' .. pane.width)
  endfor
enddef
