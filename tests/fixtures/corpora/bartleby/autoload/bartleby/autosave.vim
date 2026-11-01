vim9script

if exists('s:is_loaded') || v:version < 902 || &cp
  finish
endif
var is_loaded: bool = true

##############################################################################
# Plugin_Name: Bartleby
# autosave.vim: saves changed scrive documents while you work.
#
# Scope: only buffers whose file is in the binder folder of the open
# scrive. Other buffers are not touched. Focus shows the same buffer, so
# it is covered too.
#
# plugin/bartleby.vim calls Save on these events:
#   CursorHold, InsertLeave  At most one write per buffer every
#                            g:bartleby_autosave_interval seconds, so a
#                            low updatetime does not cause frequent
#                            writes. A write that the interval skips runs
#                            when the interval ends, see ScheduleSave.
#   FocusLost, BufLeave      Always, so nothing is left unsaved when you
#                            switch away.
#
# Save uses :update, which writes only a changed buffer, with :lockmarks,
# so the marks of your last change are kept. g:bartleby_autosave set to 0
# turns the feature off.
# License: GNU GPL 3.0
##############################################################################

import autoload 'bartleby/state.vim' as ST
import autoload 'bartleby/project.vim' as PO
import autoload 'bartleby/log.vim' as L
import autoload 'bartleby/scrivenings.vim' as SV
import autoload 'bartleby/locale/writing.vim' as MW
import autoload 'bartleby/path.vim' as PA
import 'bartleby/variables/constants.vim' as CO

const AUTOSAVE_PENDING: string = 'bartleby_autosave_pending'

var log = L.New(expand('<sfile>:t'))

# FUNCTION: Return true when the current buffer is a document of the open
# scrive.
export def IsScriveDoc(): bool
  if SV.IsScrivening(bufnr())
    return true
  endif
  if &buftype !=# '' || expand('%:p') ==# ''
    return false
  endif
  var project: PO.Project = ST.Get()
  if project is null_object
    return false
  endif
  return PA.Under(project.BinderRoot(), expand('%:p'))
enddef

# FUNCTION: Save the current buffer if it is a changed scrive document.
# With force false, skip the write when this buffer was saved less than
# g:bartleby_autosave_interval seconds ago, and schedule it instead.
export def Save(force: bool): void
  if !g:bartleby_autosave || !&modified || &readonly || !&modifiable
    return
  endif
  if !IsScriveDoc()
    return
  endif
  var now: number = localtime()
  var wait: number = g:bartleby_autosave_interval - (now - get(b:, 'bartleby_autosave_time', 0))
  if !force && wait > 0
    ScheduleSave(wait)
    return
  endif
  try
    if SV.IsScrivening(bufnr())
      # Auto-save runs from autocommands, and Vim fires no BufWriteCmd, the
      # write of a Scrivening, inside another autocommand.
      SV.SaveIfModified()
    else
      lockmarks silent update
    endif
    b:bartleby_autosave_time = now
  catch
    log.Warn(MW.AutoSaveFailed(expand("%:t"), v:exception))
  endtry
enddef

# FUNCTION: Run a write that the interval skipped once the interval ends,
# so a pause after an edit never leaves it unsaved. One timer per buffer.
# The timer saves only if that buffer is still current and Vim is not in
# Insert or Replace mode. If you left the buffer, BufLeave already saved
# it. If you are typing, InsertLeave saves it later.
def ScheduleSave(seconds: number): void
  if get(b:, AUTOSAVE_PENDING, false)
    return
  endif
  b:bartleby_autosave_pending = true
  var buf: number = bufnr('%')
  timer_start(seconds * 1000, (_) => {
    setbufvar(buf, AUTOSAVE_PENDING, false)
    if bufnr('%') == buf && mode() !~# CO.PAT_INSERT
      Save(false)
    endif
  })
enddef
