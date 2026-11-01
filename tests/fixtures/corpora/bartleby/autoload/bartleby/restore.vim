vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# restore.vim: restores the saved session of a scrive when it opens: the
# Binder, its collapsed folders, and the active document with its cursor.
# It is its own script because it drives both session.vim, which loads
# the saved state, and binder.vim, which reports its state to
# session.vim. In either of those scripts it would make the two import
# each other.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/binder.vim' as B
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/session.vim' as SS
import autoload 'bartleby/windows.vim' as W
import autoload 'bartleby/locale/data.vim' as MD

var log = L.New(expand('<sfile>:t'))

# FUNCTION: Restore the session of project, right after it opens.
export def Restore(project: PO.Project): void
  var state: SS.SessionState = SS.Load(project)

  # Show the Binder first, whatever the saved state: its buffer must exist
  # to apply the collapsed folders. Its bufhidden is hide, so closing it
  # afterward, when the saved state says closed, keeps that state for the
  # next time it opens.
  B.Show(project)
  B.ApplyCollapsedIds(state.collapsedIds)
  B.Show(project)

  if state.activeDocRelPath !=# ''
    var path: string = project.BinderRoot() .. '/' .. state.activeDocRelPath
    if filereadable(path)
      W.GoToEditorWin()
      execute 'edit ' .. fnameescape(path)
      cursor(state.cursorLine, state.cursorCol)
    else
      log.Warn(MD.SessionPreviouslyActive(path))
    endif
  endif

  if !state.binderOpen
    B.Toggle(project)
  endif
enddef
